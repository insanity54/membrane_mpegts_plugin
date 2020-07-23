defmodule WiresharkHelpers do
  @doc """
  Converts wireshark hex stream to binary that can be pasted into
  elixir code.
  """
  def hex_stream_to_bitstring(hex_stream) do
    values =
      for <<first::1-binary, second::1-binary <- hex_stream>> do
        "0x" <> first <> second
      end
      |> Enum.join(", ")

    "<<" <> values <> ">>"
  end
end
