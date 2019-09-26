defmodule Membrane.Element.MpegTS.ProgramMapTable do
  @moduledoc """
  This module is responsible for parsing Program Map Table.
  """
  defstruct [:pcr_pid, program_info: [], streams: %{}]

  @type t :: %__MODULE__{
          streams: map(),
          program_info: list(),
          pcr_pid: integer
        }

  @doc """
  Parses Program Map Table.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, :malformed_entry}
  def parse(<<
        _reserved::3,
        pcr_pid::13,
        _reserved2::4,
        program_info_length::12,
        rest::binary
      >>) do
    with {:ok, {program_info, rest}} <- parse_program_info(program_info_length, rest),
         {:ok, streams} <- parse_streams(rest) do
      result = %__MODULE__{
        program_info: program_info,
        streams: streams,
        pcr_pid: pcr_pid
      }

      {:ok, result}
    end
  end

  defp parse_program_info(descriptors, data)
  defp parse_program_info(0, date), do: {:ok, {[], date}}

  defp parse_streams(data, acc \\ %{})
  defp parse_streams(<<>>, acc), do: {:ok, acc}

  # TODO handle es_info (Page 54, Rec. ITU-T H.222.0 (03/2017))
  defp parse_streams(
         <<
           stream_type_id::8,
           _reserved::3,
           elementary_pid::13,
           _reserved1::4,
           # TODO: Use this to parse program_info
           program_info_length::12,
           _::binary-size(program_info_length),
           rest::binary
         >>,
         acc
       ) do
    result =
      Map.put(acc, elementary_pid, %{
        stream_type_id: stream_type_id,
        stream_type: parse_stream_assigment(stream_type_id)
      })

    parse_streams(rest, result)
  end

  defp parse_streams(_, _) do
    {:error, :malformed_entry}
  end

  def parse_stream_assigment(0x03), do: :mpeg_audio
  def parse_stream_assigment(0x1B), do: :h264
end
