defmodule Membrane.Element.MpegTS.Demuxer.ParserTest do
  use ExUnit.Case

  describe "When parsing table parser should" do
    test "successfully parse a valid table packet with pid in range of 0-4"
    test "successfully parse a valid table with pid in pes range but was expected to be table"
    test "return an error if invalid table packet is fed"
  end

  describe "When parsing a pes packet parser should" do
    test "successfully parse a valid pes packet"
    test "reject an invalid packet"
    test "reject a packet that has invalid pid"
    test "reject a packet with adaptation field control 0b10"
    test "reject a packet with adaptation field control 0b11 with invalid format"
    test "reject a packet with no adaptation field"
    test "reject a packet that contains no pes data"
    test "reject a packet that contains invalid optional pes"
    test "successfully parses a valid pes packet without optional fields"
  end
end
