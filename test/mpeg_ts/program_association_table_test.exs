defmodule Membrane.MPEG.TS.ProgramAssociationTableTest do
  use ExUnit.Case

  alias Membrane.MPEG.TS.Support.Fixtures
  alias Membrane.MPEG.TS.ProgramAssociationTable

  describe "Program association table parser" do
    test "parses valid packet" do
      assert {:ok, mapping} = ProgramAssociationTable.parse(Fixtures.pat())
      assert mapping == %{1 => 4096}
    end

    test "returns an error when data is not valid" do
      assert {:error, :malformed_data} = ProgramAssociationTable.parse(<<123, 32, 22, 121, 33>>)
    end
  end
end
