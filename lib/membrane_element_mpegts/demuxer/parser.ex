defmodule Membrane.Element.MPEG.TS.Demuxer.Parser do
  @moduledoc false
  # Based on:
  # * https://en.wikipedia.org/wiki/MPEG_transport_stream
  # * https://en.wikipedia.org/wiki/Packetized_elementary_stream
  # * https://en.wikipedia.org/wiki/Program-specific_information
  use Bunch
  use Membrane.Log

  @type mpegts_pid :: non_neg_integer

  @ts_packet_size 188
  @default_stream_state %{started_pts_payload: nil}

  defmodule State do
    @moduledoc false
    defstruct streams: %{}, known_tables: []

    @type t :: %__MODULE__{
            streams: map,
            known_tables: [non_neg_integer]
          }
  end

  # Parses a single packet.
  # Packet should be at least 188 bytes long, otherwise parsing will result in error.
  # Unparsed data will be returned as part of the result.
  @spec parse_single_packet(binary(), State.t()) ::
          {{:ok, {mpegts_pid, data :: binary}}, {rest :: binary, State.t()}}
          | {{:error, reason :: atom()}, {rest :: binary, State.t()}}
  def parse_single_packet(<<packet::@ts_packet_size-binary, rest::binary>>, state) do
    case parse_packet(packet, state) do
      {{:ok, {stream_pid, data}}, state} ->
        {{:ok, {stream_pid, data}}, {rest, state}}

      {{:error, _reason} = error, state} ->
        {error, {rest, state}}
    end
  end

  def parse_single_packet(rest, state), do: {{:error, :not_enough_data}, {rest, state}}

  # Parses a binary that contains sequence of packets.
  # Each packet that fails parsing shall be ignored.
  @spec parse_packets(binary, State.t()) ::
          {results :: %{mpegts_pid => [binary]}, rest :: binary, State.t()}
  def parse_packets(packets, state), do: do_parse_packets(packets, state, [])

  defp do_parse_packets(<<packet::@ts_packet_size-binary, rest::binary>>, state, acc) do
    case parse_packet(packet, state) do
      {{:ok, data}, state} ->
        do_parse_packets(rest, state, [data | acc])

      {{:error, reason}, state} ->
        """
        MPEG-TS parser encountered an error: #{inspect(reason)}
        """
        |> warn()

        do_parse_packets(rest, state, acc)
    end
  end

  defp do_parse_packets(<<rest::binary>>, state, acc) do
    acc
    |> Enum.reverse()
    |> Enum.group_by(fn {stream_pid, _data} -> stream_pid end, fn {_stream_pid, data} -> data end)
    |> Bunch.Map.map_values(&IO.iodata_to_binary/1)
    ~> {&1, rest, state}
  end

  defp parse_packet(
         <<
           0x47::8,
           _transport_error_indicator::1,
           payload_unit_start_indicator::1,
           _transport_priority::1,
           stream_pid::13,
           _transport_scrambling_control::2,
           adaptation_field_control::2,
           _continuity_counter::4,
           # 184 = 188 - header length
           optional_fields::184-binary
         >>,
         state
       ) do
    case parse_pts_optional(optional_fields, adaptation_field_control) do
      {:ok, payload} ->
        handle_parsed_payload(stream_pid, payload, payload_unit_start_indicator, state)

      error ->
        {error, put_stream(state, stream_pid)}
    end
  end

  defp parse_packet(_, state) do
    {{:error, {:invalid_packet, :pts}}, state}
  end

  defp parse_pts_optional(payload, adaptation_field_control)

  defp parse_pts_optional(payload, 0b01) do
    {:ok, payload}
  end

  defp parse_pts_optional(_adaptation_field, 0b10) do
    {:error, {:unsupported_packet, :only_adaptation_field}}
  end

  defp parse_pts_optional(optional, 0b11) do
    case optional do
      <<
        adaptation_field_length::8,
        _adaptation_field::binary-size(adaptation_field_length),
        payload::bitstring
      >> ->
        {:ok, payload}

      _ ->
        {:error, {:invalid_packet, :adaptation_field}}
    end
  end

  defp parse_pts_optional(_optional, 0b00) do
    {:error, {:invalid_packet, :adaptation_field_control}}
  end

  defp parse_adaptation_field(<<
         discontinuity_indicator::1,
         random_acces_indicator::1,
         priority_indicator::1,
         pcr_flag::1,
         opcr_flag::1,
         splicing_point::1,
         transport_private::1,
         # TODO: Handle adaptation field extension
         _adaptation_field_extension::1,
         rest::binary
       >>) do
    with {:ok, {pcr, rest}} <-
           take_bites_if_flag(rest, pcr_flag == 1, 6),
         {:ok, {opcr, rest}} <-
           take_bites_if_flag(rest, opcr_flag == 1, 6),
         {:ok, {splice_countdown, rest}} <-
           take_bites_if_flag(rest, splicing_point == 1, 1),
         {:ok, {private_data_length, rest}} <-
           take_bites_if_flag(rest, transport_private == 1, 1),
         {:ok, {private_data, _rest}} <-
           take_bites_if_flag(rest, private_data_length != nil, private_data_length) do
      adaptation_fields = %{
        discontinuity_indicator: discontinuity_indicator == 1,
        random_acces_indicator: random_acces_indicator == 1,
        priority_indicator: priority_indicator == 1,
        pcr: pcr,
        opcr: opcr,
        splicing_point: splice_countdown,
        private_data: private_data
      }

      {:ok, adaptation_fields}
    else
      _ ->
        {:error, :invalid_adaptation_field}
    end
  end

  defp take_bites_if_flag(data, true, number_of_bytes) do
    case data do
      <<data::binary-size(number_of_bytes), rest::binary>> ->
        {:ok, {data, rest}}

      _ ->
        {:error, :invalid_packet}
    end
  end

  defp take_bites_if_flag(data, false, _number_of_bytes), do: {:ok, {nil, data}}

  defp handle_parsed_payload(stream_pid, payload, payload_unit_start_indicator, state) do
    cond do
      stream_pid in 0x0000..0x0004 or stream_pid in state.known_tables ->
        <<_pointer::8, payload::binary>> = payload
        known_tables = state.known_tables |> List.delete(stream_pid)
        {{:ok, {stream_pid, payload}}, %{state | known_tables: known_tables}}

      stream_pid in 0x0020..0x1FFA or stream_pid in 0x1FFC..0x1FFE ->
        stream_state = state.streams[stream_pid] || @default_stream_state

        payload
        |> parse_pts_payload(payload_unit_start_indicator, stream_state)
        |> handle_pts_payload(stream_pid, state)

      stream_pid == 0x1FFF ->
        {:null_packet, state}

      true ->
        {{:error, :unsuported_stream_pid}, state}
    end
  end

  defp parse_pts_payload(<<1::24, _::bitstring>> = payload, 0b1, stream_state) do
    with {:ok, payload} <- parse_pes_packet(payload) do
      {:ok, {payload, %{stream_state | started_pts_payload: :pes}}}
    end
  end

  defp parse_pts_payload(payload, 0b0, %{started_pts_payload: :pes} = stream_state) do
    {:ok, {payload, stream_state}}
  end

  defp parse_pts_payload(_payload, _pusi, _stream_state) do
    {:error, {:unsupported_packet, :not_pes}}
  end

  defp handle_pts_payload({:ok, {data, stream_state}}, stream_pid, state) do
    {{:ok, {stream_pid, data}}, put_stream(state, stream_pid, stream_state)}
  end

  defp handle_pts_payload({:error, _} = error, stream_pid, state) do
    {error, put_stream(state, stream_pid)}
  end

  defp parse_pes_packet(<<
         1::24,
         _stream_id::8,
         _packet_length::16,
         optional_fields::bitstring
       >>) do
    parse_pes_optional(optional_fields)
  end

  defp parse_pes_packet(_), do: {:error, {:invalid_packet, :pes}}

  defp parse_pes_optional(<<0b10::2, optional::bitstring>>) do
    case optional do
      <<
        _scrambling_control::2,
        _priority::1,
        _data_alignment_indicator::1,
        _copyright::1,
        _original_or_copy::1,
        _pts_dts_indicator::2,
        _escr_flag::1,
        _es_rate_flag::1,
        _dsm_trick_mode_flag::1,
        _additional_copy_info_flag::1,
        _crc_flag::1,
        _extension_flag::1,
        pes_header_length::8,
        _optional_fields::binary-size(pes_header_length),
        data::binary
      >> ->
        {:ok, data}

      _ ->
        {:error, {:invalid_packet, :pes_optional}}
    end
  end

  defp parse_pes_optional(optional) do
    {:ok, optional}
  end

  defp put_stream(state, stream_pid, stream \\ @default_stream_state) do
    %State{state | streams: Map.put(state.streams, stream_pid, stream)}
  end
end
