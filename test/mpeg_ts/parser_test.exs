defmodule Membrane.Element.MpegTS.Demuxer.ParserTest do
  use ExUnit.Case

  alias Membrane.Element.MpegTS.Demuxer.Parser
  alias Parser.State
  alias Membrane.Element.MpegTS.Support.Fixtures

  setup do
    [state: %Parser.State{}]
  end

  describe "When parsing a table parser should" do
    test "successfully parse a valid table packet with pid in range of 0-4", %{state: state} do
      raw_data = Fixtures.pat_packet()
      assert {:ok, {data, "", ^state}} = Parser.parse_single_packet(raw_data, state)
      assert data = {0, Fixtures.pat_payload()}
    end

    test "successfully parse a valid table with pid in pes range but was expected to be table", %{
      state: state
    } do
      state = %State{state | known_tables: [0x1000]}
      raw_data = Fixtures.pmt_packet()
      assert {:ok, {data, "", result_state}} = Parser.parse_single_packet(raw_data, state)
      assert %State{state | known_tables: []} == result_state
      assert {4096, with_padding} = data
      assert String.starts_with?(with_padding, Fixtures.pmt_payload())
    end

    test "return an error if invalid table packet is fed", %{state: state} do
      assert {:error, :packet_malformed} = Parser.parse_single_packet("Garbage", state)
    end
  end

  describe "When parsing a pes packet parser should" do
    test "successfully parse a valid pes packet", %{state: state} do
      expected_state = %State{state | streams: %{256 => %{started_pts_payload: :pes}}}

      assert {:ok, {data, "", ^expected_state}} =
               Parser.parse_single_packet(Fixtures.data_packet_video(), state)
    end

    # test "reject an invalid packet"
    # test "reject a packet that has invalid pid"
    # test "reject a packet with adaptation field control 0b10"
    # test "reject a packet with adaptation field control 0b11 with invalid format"
    # test "reject a packet with no adaptation field"
    # test "reject a packet that contains no pes data"
    # test "reject a packet that contains invalid optional pes"
    # test "successfully parses a valid pes packet without optional fields"
  end
end
