defmodule Membrane.Element.MPEG.TS.DemuxerTest do
  use ExUnit.Case

  # TODO: Marked for refactoring

  alias Membrane.Buffer
  alias Membrane.Element.MPEG.TS.Demuxer
  alias Membrane.Element.MPEG.TS.Support.Fixtures
  alias Demuxer.State

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

    test "should parse pmt and transition to next state if that is only program", %{state: state} do
      expected_mapping = %{
        1 => %Membrane.Element.MPEG.TS.ProgramMapTable{
          pcr_pid: 256,
          program_info: [],
          streams: %{
            256 => %{stream_type: :h264, stream_type_id: 27},
            257 => %{stream_type: :mpeg_audio, stream_type_id: 3}
          }
        }
      }

      packet = Fixtures.pmt_packet()
      buffer = %Membrane.Buffer{payload: packet}
      parser = %{state.parser | known_tables: [0x1000]}
      state = %State{state | parser: parser}
      assert {{:ok, actions}, state} = Demuxer.handle_process(:input, buffer, nil, state)
      assert [notify: {:mpeg_ts_mapping_req, mapping}] = actions

      assert expected_mapping == mapping

      assert state == %Membrane.Element.MPEG.TS.Demuxer.State{
               configuration: expected_mapping,
               work_state: :awaiting_mapping
             }
    end

    test "orders more data if it runs out of queue", %{state: state} do
      tail = <<122, 123, 124, 125>>
      packet = Fixtures.pat_packet() <> tail
      buffer = %Membrane.Buffer{payload: packet}
      assert {{:ok, actions}, result_state} = Demuxer.handle_process(:input, buffer, nil, state)
      assert [demand: :input] == actions
      assert result_state == %State{state | queue: tail}
    end

    test "should parse pmt and wait for subsequent pmts if they are to expected", %{state: state} do
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
      [state: %State{work_state: :awaiting_mapping}]
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

      assert final_state.queue == base
    end

    test "should not process buffers", %{state: state} do
      queue = "queue"
      state = %State{state | queue: queue}
      appendix = "should_be_last"

      assert {:ok, result_state} =
               Demuxer.handle_process(:input, %Buffer{payload: appendix}, nil, state)

      assert result_state == %State{state | queue: queue <> appendix}
    end

    test "should transition to working state when received a proper message", %{state: state} do
      config = 1

      assert {{:ok, actions}, result_state} =
               Demuxer.handle_other({:mpeg_ts_mapping, config}, nil, state)

      assert [demand: :input] == actions

      assert %Membrane.Element.MPEG.TS.Demuxer.State{
               configuration: config,
               work_state: :working
             } == result_state
    end
  end

  describe "When working demuxer" do
    setup _ do
      [state: %State{work_state: :working}]
    end

    test "should demand when both pads requested data", %{state: state} do
      assert {{:ok, demand: {:input, demand}}, state} =
               Demuxer.handle_demand({:dynamic, :output, 1}, 10, :buffers, nil, state)

      assert is_function(demand)
    end

    test "should process buffers and send them to according pads", %{state: state} do
      pads_count = 10

      example_configuration =
        0..pads_count
        |> Enum.map(fn num ->
          {{:output, num}, 255 + num}
        end)
        |> Enum.into(%{})

      dynamic_pads =
        0..pads_count
        |> Enum.map(fn num -> {{:dynamic, :output, num}, :pad_data} end)
        |> Enum.into(%{})

      ctx = %{
        pads:
          %{
            :input => :pad_data
          }
          |> Map.merge(dynamic_pads)
      }

      state = %State{state | configuration: example_configuration}

      example_configuration
      |> Enum.each(fn {{pad, number}, pid} ->
        payload = "#{pad}, #{number}"
        packet = Fixtures.data_packet(pid, payload)
        buffer = %Buffer{payload: packet}

        assert {{:ok, actions}, state} = Demuxer.handle_process(:input, buffer, ctx, state)

        assert [
                 buffer: {{:dynamic, ^pad, ^number}, buffers},
                 redemand: {:dynamic, :output, 0}
               ] = actions

        assert [%Membrane.Buffer{metadata: %{}, payload: received_payload}] = buffers
        assert String.starts_with?(received_payload, payload)
      end)
    end
  end

  describe "When element is being configured" do
    test "it should ignore demands" do
      [:waiting_pat, :waiting_pmt, :awaiting_mapping]
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
      assert state.queue == ""
    end

    test "in case of an error next buffer is demanded if queue is empty" do
      garbage = Fixtures.data_packet(5, "garbage")

      assert {{:ok, actions}, state} =
               Demuxer.handle_process(:input, %Buffer{payload: garbage}, nil, %State{})

      assert actions == [demand: :input]
      assert state.work_state == :waiting_pat
      assert state.queue == ""
    end
  end

  test "When going from prepared to playing demands a buffer to kickstart configuration" do
    assert {{:ok, demand: :input}, %State{}} = Demuxer.handle_prepared_to_playing(nil, %State{})
  end
end
