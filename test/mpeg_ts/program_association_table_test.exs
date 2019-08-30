defmodule Membrane.Element.MpegTS.ProgramAssociationTableTest do
  use ExUnit.Case

  alias Membrane.Element.MpegTS.Support.Fixtures
  alias Membrane.Element.MpegTS.ProgramAssociationTable

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
