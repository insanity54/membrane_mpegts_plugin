defmodule Membrane.Element.MpegTS.Demuxer do
  @moduledoc """
  Demuxes MpegTS stream.
  """
  use Membrane.Element.Base.Filter

  alias __MODULE__.Parser
  alias Membrane.Element.MpegTS.Table
  alias Membrane.Buffer

  @ts_packet_size 188

  defmodule State do
    @moduledoc false
    defstruct queue: <<>>,
              parser: Parser.init_state(),
              demands: MapSet.new(),
              work_state: :waiting_pat,
              configuration: %{}

    @type work_state_t :: :waiting_pat | :waiting_pmt | :waiting_link | :working
  end

  def_output_pad :output,
    availability: :on_request,
    caps: :any

  def_input_pad :input, caps: :any, demand_unit: :buffers

  @impl true
  def handle_demand(_pad, _size, _unit, _ctx, %State{work_state: work_state} = state)
      when work_state in [:waiting_pat, :waiting_pmt] do
    {{:ok, demand: {:input, 1}}, state}
  end

  def handle_demand(pad, size, _unit, _ctx, %State{work_state: :working} = state) do
    demands = state.demands |> MapSet.put(pad)

    if MapSet.size(demands) == 2 do
      {{:ok, demand: {:input, 2 * size}}, %{state | demands: MapSet.new()}}
    else
      {:ok, %{state | demands: demands}}
    end
  end

  @impl true
  def handle_init(_) do
    {:ok, %State{}}
  end

  @impl true
  def handle_other({:config_demuxer, configuration}, _ctx, state) do
    state = %State{state | configuration: configuration, work_state: :working}
    {{:ok, demand: :input}, state}
  end

  @impl true
  def handle_process(
        :input,
        %Buffer{payload: payload},
        _ctx,
        %State{work_state: work_state} = state
      )
      when work_state in [:waiting_pmt, :waiting_pat] do
    %{state | queue: state.queue <> payload}
    |> handle_startup()
  end

  def handle_process(
        :input,
        %Buffer{payload: payload},
        _ctx,
        %State{work_state: :waiting_link, queue: q} = state
      ) do
    state = %State{state | queue: q <> payload}
    {:ok, state}
  end

  def handle_process(:input, buffer, ctx, %State{work_state: :working} = state) do
    {payloads, queue, parser} = Parser.parse_packets(state.queue <> buffer.payload, state.parser)

    payloads =
      payloads
      |> Enum.group_by(fn {pid, _payload} -> pid end, fn {_pid, payload} -> payload end)

    parsed_stream_pids = Map.keys(payloads)

    buffer_actions =
      ctx.pads
      |> Map.keys()
      |> Enum.filter(fn
        {:dynamic, pad_name, pad_number} ->
          state.configuration[{pad_name, pad_number}] in parsed_stream_pids

        _ ->
          false
      end)
      |> Enum.map(fn {:dynamic, pad_name, pad_number} = pad ->
        stream_pid = state.configuration[{pad_name, pad_number}]

        buffers =
          payloads[stream_pid]
          |> Enum.map(fn payload -> %Buffer{payload: payload} end)

        {:buffer, {pad, buffers}}
      end)

    {{:ok, buffer_actions ++ [redemand: {:dynamic, :output, 0}]},
     %State{state | queue: queue, parser: parser}}
  end

  defp handle_startup(%State{queue: queue} = state) when byte_size(queue) < 188 do
    {{:ok, demand: {:input, 1}}, state}
  end

  defp handle_startup(state) do
    case Parser.parse_single_packet(state.queue, state.parser) do
      {:ok, {{_pid, table_data}, rest, parser_state}} ->
        %State{state | parser: parser_state, queue: rest}
        |> parse_table(table_data)
        |> handle_parse_result()

      {{:error, _reason}, {rest, parser_state}} ->
        %State{state | queue: rest, parser: parser_state}
        |> handle_startup
    end
  end

  defp parse_table(state, table_data) do
    case Membrane.Element.MpegTS.Table.parse(table_data) do
      {:ok, {header, data, _crc}} ->
        handle_table(header, data, state)

      {:error, _} = error ->
        {error, state}
    end
  end

  defp handle_table(%Table{table_id: 0}, data, %State{work_state: :waiting_pat} = state) do
    parser = %{state.parser | known_tables: Map.values(data)}
    state = %State{state | work_state: :waiting_pmt, parser: parser}

    {:ok, state}
  end

  defp handle_table(%Table{table_id: 2} = header, data, %State{work_state: :waiting_pmt} = state) do
    configuration = Map.put(state.configuration, header.transport_stream_id, data)
    state = %State{state | configuration: configuration}

    case state.parser.known_tables do
      [] ->
        state = %State{state | work_state: :waiting_link}
        {{:ok, notify: {:mpeg_mapping, configuration}}, state}

      _ ->
        {:ok, state}
    end
  end

  defp handle_table(_, _, state) do
    {{:error, :wrong_table}, state}
  end

  defp handle_parse_result({:ok, %State{work_state: ws, queue: queue} = state})
       when ws in [:waiting_pat, :waiting_pmt] do
    if queue |> byte_size() < @ts_packet_size do
      {{:ok, demand: {:input, 1}}, state}
    else
      handle_startup(state)
    end
  end

  defp handle_parse_result({{:error, _reason}, state}), do: state |> handle_startup()
  defp handle_parse_result({{:ok, _actions}, _state} = result), do: result
end
