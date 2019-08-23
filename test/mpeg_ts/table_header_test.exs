defmodule Membrane.Element.MpegTS.TableHeaderTest do
  use ExUnit.Case
  alias Membrane.Element.MpegTS.Support.Fixtures
  alias Membrane.Element.MpegTS.TableHeader

  describe "Table header parser" do
    test "parses valid PAT header" do
      assert {:ok, {header, data, crc}} = TableHeader.parse(Fixtures.pat_packet())

      assert header == %TableHeader{
               table_id: 0,
               section_syntax_indicator: true,
               section_length: 13,
               transport_stream_id: 1,
               version_number: 0,
               current_next_indicator: true,
               section_number: 0,
               last_section_number: 0
             }

      assert data == Fixtures.pat()
      assert crc == <<0x2A, 0xB1, 0x04, 0xB2>>
    end

    test "parses valid PMT header" do
      assert {:ok, {header, data, crc}} = TableHeader.parse(Fixtures.pmt_packet())

      assert header == %TableHeader{
               table_id: 2,
               section_syntax_indicator: true,
               section_length: 23,
               transport_stream_id: 1,
               version_number: 0,
               current_next_indicator: true,
               section_number: 0,
               last_section_number: 0
             }

      assert data == Fixtures.pmt()
    end

    test "returns an error when data is invalid" do
      assert {:error, :malformed_packet} == TableHeader.parse(<<123, 231, 132>>)
    end
  end
end
