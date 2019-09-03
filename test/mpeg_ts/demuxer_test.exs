defmodule Membrane.Element.MpegTS.DemuxerTest do
  use ExUnit.Case

  alias Membrane.Element.MpegTS.Demuxer
  alias Membrane.Element.MpegTS.Support.Fixtures
  alias Demuxer.State

  describe "When waiting for program association table demuxer" do
    setup _ do
      [state: %State{work_state: :waiting_pat}]
    end

    test "should demand exactly one buffer", %{state: state} do
      assert {{:ok, actions}, state} = Demuxer.handle_demand(:input, 10, :buffers, nil, state)
      assert actions == [demand: {:input, 1}]
    end

    test "should parse pat and transition to waiting for pmt state", %{state: state} do
      packet = Fixtures.pat_packet()
      buffer = %Membrane.Buffer{payload: packet}
      assert {{:ok, actions}, result_state} = Demuxer.handle_process(:input, buffer, nil, state)
      assert [demand: {:input, 1}] == actions
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

    test "should demand exactly one buffer", %{state: state} do
      assert {{:ok, actions}, state} = Demuxer.handle_demand(:input, 10, :buffers, nil, state)
      assert actions == [demand: {:input, 1}]
    end

    test "should parse pmt and transition to next state if that is only program", %{state: state} do
      packet = Fixtures.pmt_packet()
      buffer = %Membrane.Buffer{payload: packet}
      parser = %{state.parser | known_tables: [0x1000]}
      state = %State{state | parser: parser}
      assert {{:ok, actions}, state} = Demuxer.handle_process(:input, buffer, nil, state)
      assert [notify: {:mpeg_mapping, mapping}] = actions

      assert %{
               1 => %Membrane.Element.MpegTS.ProgramMapTable{
                 pcr_pid: 256,
                 program_info: [],
                 streams: %{
                   256 => %{stream_type: :h264, stream_type_id: 27},
                   257 => %{stream_type: :mpeg_audio, stream_type_id: 3}
                 }
               }
             } == mapping

      assert state == %Membrane.Element.MpegTS.Demuxer.State{
               configuration: %{
                 1 => %Membrane.Element.MpegTS.ProgramMapTable{
                   pcr_pid: 256,
                   program_info: [],
                   streams: %{
                     256 => %{stream_type: :h264, stream_type_id: 27},
                     257 => %{stream_type: :mpeg_audio, stream_type_id: 3}
                   }
                 }
               },
               queue: "",
               work_state: :waiting_link
             }
    end

    test "orders more data if it runs out of queue", %{state: state} do
      tail = <<122, 123, 124, 125>>
      packet = Fixtures.pat_packet() <> tail
      buffer = %Membrane.Buffer{payload: packet}
      assert {{:ok, actions}, result_state} = Demuxer.handle_process(:input, buffer, nil, state)
      assert [demand: {:input, 1}] == actions
      assert result_state == %State{state | queue: tail}
    end

    test "should parse pmt and wait for subsequent pmts if they are to expected", %{state: state} do
      packet = Fixtures.pmt_packet()
      buffer = %Membrane.Buffer{payload: packet}
      parser = %{state.parser | known_tables: [0x1000, 0x1001]}
      state = %State{state | parser: parser}
      assert {{:ok, actions}, state} = Demuxer.handle_process(:input, buffer, nil, state)
      assert [demand: {:input, 1}] = actions

      assert %State{
               configuration: accumulated_config,
               parser: %{known_tables: [4097], streams: %{}},
               work_state: :waiting_pmt
             } = state

      assert %{
               1 => %Membrane.Element.MpegTS.ProgramMapTable{
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
    test "should not accept demands"
    test "should not process buffers"
    test "should transition to working state when received a proper message"
  end

  describe "When working demuxer" do
    test "should demand when both pads requested data"
    test "should process buffers and send them to according pads"
  end
end
