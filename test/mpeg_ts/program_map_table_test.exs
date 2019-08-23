defmodule Membrane.Element.MpegTS.ProgramMapTableTest do
  use ExUnit.Case

  alias Membrane.Element.MpegTS.{ProgramMapTable, TableHeader}
  alias Membrane.Element.MpegTS.Support.Fixtures

  describe "Program Map Table parser" do
    test "parses valid program map table with stream info but without program info" do
      assert {:ok, table} = ProgramMapTable.parse(Fixtures.pmt())

      assert %ProgramMapTable{
               pcr_pid: 0x0100,
               program_info: [],
               streams: %{
                 256 => %{stream_type: :h264, stream_type_id: 0x1B},
                 257 => %{stream_type: :mpeg_audio, stream_type_id: 0x03}
               }
             } = table
    end
  end
end
