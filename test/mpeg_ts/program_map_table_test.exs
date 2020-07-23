defmodule Membrane.MPEG.TS.ProgramMapTableTest do
  use ExUnit.Case

  alias Membrane.MPEG.TS.ProgramMapTable
  alias Membrane.MPEG.TS.Support.Fixtures

  # TODO add more exhaustive tests
  describe "Program Map Table parser" do
    test "parses valid program map table with stream info but without program info" do
      assert {:ok, table} = ProgramMapTable.parse(Fixtures.pmt())

      assert %ProgramMapTable{
               pcr_pid: 0x0100,
               program_info: [],
               streams: %{
                 256 => %{stream_type: :H264, stream_type_id: 0x1B},
                 257 => %{stream_type: :MPEG1_AUDIO, stream_type_id: 0x03}
               }
             } = table
    end

    test "returns an error when map table is malformed" do
      valid_pmt = Fixtures.pmt()
      garbage_size = byte_size(valid_pmt) - 3
      <<garbage::binary-size(garbage_size), _::binary>> = valid_pmt
      assert {:error, :malformed_entry} = ProgramMapTable.parse(garbage)
    end
  end
end
