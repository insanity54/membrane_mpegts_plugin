defmodule Membrane.Element.MpegTS.ProgramAssociationTable do
  @type entry :: %{
          program_number: 0..65535,
          program_map_pid: 0..8191
        }

  @spec parse(binary) :: {:ok, map()} | {:error, :malformed_data}
  def parse(data) when rem(byte_size(data), 4) == 0 do
    programs =
      for <<program_number::16, _reserved::3, pid::13 <- data>> do
        {program_number, pid}
      end
      |> Enum.into(%{})

    {:ok, programs}
  end

  def parse(_) do
    {:error, :malformed_data}
  end
end
