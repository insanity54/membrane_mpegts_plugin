defmodule Membrane.Element.MPEG.TS.ProgramAssociationTable do
  @moduledoc """
  This module is responsible for parsing Program Association Table.
  """
  @type entry :: %{
          program_number: 0..65_535,
          program_map_pid: 0..8191
        }

  @entry_length 4

  @doc """
  Parses Program Association Table data.

  Each entry should be 4 bytes long. If provided data length is not divisible
  by entry length an error shall be returned.
  """
  @spec parse(binary) :: {:ok, map()} | {:error, :malformed_data}
  def parse(data) when rem(byte_size(data), @entry_length) == 0 do
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
