defmodule Membrane.Element.MpegTS.Table do
  @moduledoc """
  This module contains functions for parsing MPEG-TS tables.
  """

  @enforce_keys [
    :table_id,
    :section_syntax_indicator,
    :section_length,
    :transport_stream_id,
    :version_number,
    :current_next_indicator,
    :section_number,
    :last_section_number
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          table_id: 0..3 | 16..31,
          section_syntax_indicator: boolean,
          section_length: 0..1021,
          transport_stream_id: 0..65535,
          version_number: 0..31,
          current_next_indicator: boolean,
          section_number: 0..255,
          last_section_number: 0..255
        }

  @crc_length 4
  @remaining_header_length 5

  @doc """
  Parser an MPEG-TS table.

  Attempts to parse it's contents according table id value. If table is not recognized
  it's raw binary data is returned.
  """
  @spec parse(any) :: {:ok, {t(), binary | map, <<_::32>>}} | {:error, :malformed_packet}
  def parse(data) do
    with {:ok, {header, data}} <- parse_header(data) do
      content_length = header.section_length - @crc_length - @remaining_header_length

      case data do
        <<raw_data::binary-size(content_length), crc::4-binary, _::binary>> ->
          data =
            case parse_table_data(header.table_id, raw_data) do
              {:ok, data} ->
                data

              {:error, :unsuported_table_type} ->
                raw_data
            end

          {:ok, {header, data, crc}}

        _ ->
          {:error, :malformed_packet}
      end
    end
  end

  @doc """
  Parses data that preceeds all the MPEG-TS tables.
  """
  @spec parse_header(any) :: {:ok, {t(), binary}} | {:error, :malformed_header}
  def parse_header(<<
        table_id::8,
        section_syntax_indicator::1,
        0::1,
        _r1::2,
        # section length starts with 00
        0::2,
        section_length::10,
        transport_stream_id::16,
        _r2::2,
        version_number::5,
        current_next_indicator::1,
        section_number::8,
        last_section_number::8,
        rest::binary
      >>) do
    header = %__MODULE__{
      table_id: table_id,
      section_syntax_indicator: section_syntax_indicator == 1,
      section_length: section_length,
      transport_stream_id: transport_stream_id,
      version_number: version_number,
      current_next_indicator: current_next_indicator == 1,
      section_number: section_number,
      last_section_number: last_section_number
    }

    {:ok, {header, rest}}
  end

  def parse_header(_), do: {:error, :malformed_header}

  defp parse_table_data(0x00, data),
    do: Membrane.Element.MpegTS.ProgramAssociationTable.parse(data)

  defp parse_table_data(0x02, data),
    do: Membrane.Element.MpegTS.ProgramMapTable.parse(data)

  defp parse_table_data(_, _),
    do: {:error, :unsuported_table_type}
end
