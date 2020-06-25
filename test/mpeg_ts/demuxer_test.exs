defmodule Membrane.Element.MPEG.TS.DemuxerTest do
  use ExUnit.Case

  # TODO: Marked for refactoring

  alias Membrane.Buffer
  alias Membrane.Element.MPEG.TS.Demuxer
  alias Membrane.Element.MPEG.TS.Support.Fixtures
  alias Demuxer.State
  alias Membrane.Pad
  require Pad

  @demand_in_buffers 10
  @context_with_pads %{
    pads: %{Pad.ref(:output, 1) => %{demand: @demand_in_buffers, other_demand_unit: :buffers}}
  }

  describe "When waiting for program association table demuxer" do
    setup _ do
      [state: %State{work_state: :waiting_pat}]
    end

    test "should parse pat and transition to waiting for pmt state", %{state: state} do
      packet = Fixtures.pat_packet()
      buffer = %Membrane.Buffer{payload: packet}
      assert {{:ok, actions}, result_state} = Demuxer.handle_process(:input, buffer, nil, state)
      assert [demand: :input] == actions
      parser_state = %{state.parser | known_tables: [4096]}

      assert result_state == %State{
               state
               | work_state: :waiting_pmt,
                 parser: parser_state
             }
    end
  end

  describe "When waiting for program maping table demuxer" do
    setup _ do
      [state: %State{work_state: :waiting_pmt}]
    end

    test "should parse PMT and transition to next state if that is the only program", %{
      state: state
    } do
      packet = Fixtures.pmt_packet()
      buffer = %Membrane.Buffer{payload: packet}
      parser = %{state.parser | known_tables: [0x1000]}
      state = %State{state | parser: parser}
      assert {{:ok, actions}, state} = Demuxer.handle_process(:input, buffer, nil, state)
      assert [notify: {:mpeg_ts_stream_info, config}] = actions

      assert state == %Membrane.Element.MPEG.TS.Demuxer.State{
               configuration: config,
               work_state: :awaiting_linking
             }
    end

    test "orders more data if it runs out of queue", %{state: state} do
      tail = <<122, 123, 124, 125>>
      packet = Fixtures.pat_packet() <> tail
      buffer = %Membrane.Buffer{payload: packet}
      assert {{:ok, actions}, result_state} = Demuxer.handle_process(:input, buffer, nil, state)
      assert [demand: :input] == actions
      assert result_state == %State{state | data_queue: tail}
    end

    test "should parse PMT and wait for subsequent PMTs if they are expected", %{state: state} do
      packet = Fixtures.pmt_packet()
      buffer = %Membrane.Buffer{payload: packet}
      parser = %{state.parser | known_tables: [0x1000, 0x1001]}
      state = %State{state | parser: parser}

      assert {{:ok, actions}, state} = Demuxer.handle_process(:input, buffer, nil, state)
      assert [demand: :input] = actions

      assert %State{
               configuration: accumulated_config,
               parser: %{known_tables: [4097], streams: %{}},
               work_state: :waiting_pmt
             } = state

      assert %{
               1 => %Membrane.Element.MPEG.TS.ProgramMapTable{
                 pcr_pid: 256,
                 program_info: [],
                 streams: %{
                   256 => %{stream_type: :h264, stream_type_id: 27},
                   257 => %{stream_type: :mpeg_audio, stream_type_id: 3}
                 }
               }
             } == accumulated_config
    end
  end

  describe "When waiting for links demuxer" do
    setup _ do
      [state: %State{work_state: :awaiting_linking}]
    end

    test "accumulates buffers so they can be processed when pipeline responds", %{state: state} do
      base = <<1, 2, 3, 4, 5, 6>>

      final_state =
        base
        |> :binary.bin_to_list()
        |> Enum.reduce(state, fn elem, acc ->
          buffer = %Buffer{payload: <<elem>>}
          assert {:ok, state} = Demuxer.handle_process(:input, buffer, nil, acc)
          state
        end)

      assert final_state.data_queue == base
    end

    test "should not process buffers", %{state: state} do
      data_queue = "queue"
      state = %State{state | data_queue: data_queue}
      appendix = "should_be_last"

      assert {:ok, result_state} =
               Demuxer.handle_process(:input, %Buffer{payload: appendix}, nil, state)

      assert result_state == %State{state | data_queue: data_queue <> appendix}
    end

    test "should transition to working state after receiving a proper message", %{state: state} do
      assert {{:ok, actions}, result_state} =
               Demuxer.handle_other(:pads_ready, @context_with_pads, state)

      assert [demand: {:input, @demand_in_buffers}] == actions

      assert %Membrane.Element.MPEG.TS.Demuxer.State{
               work_state: :working
             } == result_state
    end

    test "should not change state unless all pads are linked" do
      config = %{
        1 => %{
          streams: %{
            2 => :stream_info,
            3 => :stream_info
          }
        }
      }

      state = %State{
        work_state: :awaiting_linking,
        configuration: config
      }

      ctx = %{
        pads: %{
          Pad.ref(:output, 3) => :pad_data
        }
      }

      assert {:ok, state} ==
               Demuxer.handle_pad_added(Pad.ref(:output, 2), ctx, state)
    end

    test "should transition to working upon linking all pads" do
      state = %State{
        work_state: :awaiting_linking,
        configuration: %{
          1 => %{
            streams: %{
              2 => :stream_info,
              3 => :stream_info
            }
          }
        }
      }

      ctx = %{
        pads: %{
          Pad.ref(:output, 2) => %{demand: @demand_in_buffers, other_demand_unit: :buffers},
          Pad.ref(:output, 3) => %{demand: 300, other_demand_unit: :bytes}
        }
      }

      assert {{:ok, [demand: {:input, @demand_in_buffers + 2}]},
              %State{state | work_state: :working}} ==
               Demuxer.handle_pad_added(Pad.ref(:output, 2), ctx, state)
    end

    # TODO finish this when core issue with handle_pad_added/3 has all pads in context is fixed
    # test "adding pads in states `:waiting_pat` and `:waiting_pmt` should have no effect"
  end

  describe "When working demuxer" do
    setup _ do
      [state: %State{work_state: :working}]
    end

    test "should demand when both pads requested data", %{state: state} do
      new_demand = 10
      old_demand = 3

      assert {{:ok, demand: {:input, demand}}, state} =
               Demuxer.handle_demand(
                 {:dynamic, :output, 1},
                 old_demand,
                 :buffers,
                 %{incoming_demand: new_demand},
                 state
               )

      assert is_function(demand)
      assert demand.(old_demand) == new_demand + old_demand
    end

    test "should process buffers and send them to according pads", %{state: state} do
      pads_count = 10

      configuration = %{
        0 => %Membrane.Element.MPEG.TS.ProgramMapTable{
          pcr_pid: 256,
          program_info: [],
          streams: %{
            256 => %{stream_type: :h264, stream_type_id: 27},
            257 => %{stream_type: :mpeg_audio, stream_type_id: 3}
          }
        },
        1 => %Membrane.Element.MPEG.TS.ProgramMapTable{
          pcr_pid: 24,
          program_info: [],
          streams: %{
            257 => %{stream_type: :h264, stream_type_id: 27},
            258 => %{stream_type: :mpeg_audio, stream_type_id: 3}
          }
        }
      }

      dynamic_pads =
        256..(256 + pads_count)
        |> Enum.map(fn num -> {Pad.ref(:output, num), :pad_data} end)
        |> Enum.into(%{})

      expected_redemand = dynamic_pads |> Map.keys()

      ctx = %{
        pads:
          %{
            :input => :pad_data
          }
          |> Map.merge(dynamic_pads)
      }

      state = %State{state | configuration: configuration}

      for {program_id, pmt} <- configuration,
          {sid, _stream_spec} <- pmt.streams do
        payload = "#{program_id}, #{sid}"
        packet = Fixtures.data_packet(sid, payload)
        buffer = %Buffer{payload: packet}

        assert {{:ok, actions}, state} = Demuxer.handle_process(:input, buffer, ctx, state)

        assert [
                 buffer: {Pad.ref(pad, number), buffers},
                 redemand: ^expected_redemand
               ] = actions

        assert [%Membrane.Buffer{metadata: %{}, payload: received_payload}] = buffers
        assert String.starts_with?(received_payload, payload)
      end
    end
  end

  describe "When element is being configured" do
    test "it should ignore demands" do
      [:waiting_pat, :waiting_pmt, :awaiting_linking]
      |> Enum.each(fn work_state ->
        state = %State{work_state: work_state}

        assert {:ok, state} ==
                 Demuxer.handle_demand({:dynamic, :output, 1}, 1, :buffers, nil, state)
      end)
    end

    test "in case of an error next packet is processed from the queue" do
      packet = Fixtures.pat_packet()
      garbage = Fixtures.data_packet(5, "garbage")
      payload = garbage <> packet

      assert {{:ok, actions}, state} =
               Demuxer.handle_process(:input, %Buffer{payload: payload}, nil, %State{})

      assert actions == [demand: :input]
      assert state.work_state == :waiting_pmt
      assert state.data_queue == ""
    end

    test "in case of an error next buffer is demanded if queue is empty" do
      garbage = Fixtures.data_packet(5, "garbage")

      assert {{:ok, actions}, state} =
               Demuxer.handle_process(:input, %Buffer{payload: garbage}, nil, %State{})

      assert actions == [demand: :input]
      assert state.work_state == :waiting_pat
      assert state.data_queue == ""
    end
  end

  test "When going from prepared to playing demands a buffer to kickstart configuration" do
    assert {{:ok, demand: :input}, %State{}} = Demuxer.handle_prepared_to_playing(nil, %State{})
  end
end
