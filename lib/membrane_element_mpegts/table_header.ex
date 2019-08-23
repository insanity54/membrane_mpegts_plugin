defmodule Membrane.Element.MpegTS.TableHeader do
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
  @spec parse(any) :: {:ok, {t(), integer, byte}} | {:error, :malformed_packet}

  def parse(<<
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
    content_length = section_length - @crc_length - @remaining_header_length

    case rest do
      <<data::binary-size(content_length), crc::4-binary, _::binary>> ->
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

        {:ok, {header, data, crc}}
    end
  end

  def parse(_), do: {:error, :malformed_packet}

  # TODO move following to pat module
end
