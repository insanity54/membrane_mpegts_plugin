defmodule Membrane.Element.MPEG.TS.Demuxer do
  @moduledoc """
  Demuxes MPEG TS stream.

  After transition into playing state, this element will wait for
  [Program Association Table](https://en.wikipedia.org/wiki/MPEG_transport_stream#PAT) and
  [Program Mapping Table](https://en.wikipedia.org/wiki/MPEG_transport_stream#PMT).
  Upon succesfful parsing of those tables it will send a message to the pipeline in format
  `{:mpeg_ts_mapping_req, configuration}`, where configuration contains data read from tables.

  Configuration sent by element to pipeline should have following shape
  ```
  %{
    program_id => %Membrane.Element.MPEG.TS.ProgramMapTable{
      pcr_pid: 256,
      program_info: [],
      streams: %{
        256 => %{stream_type: :h264, stream_type_id: 27},
        257 => %{stream_type: :mpeg_audio, stream_type_id: 3}
      }
    }
  }
  ```
  """
  use Membrane.Filter

  alias __MODULE__.Parser
  alias Membrane.Buffer
  alias Membrane.Element.MPEG.TS.Table
  alias Membrane.Element.MPEG.TS.{ProgramAssociationTable, ProgramMapTable}

  @typedoc """
  This types represents structure that is sent by this element to pipeline.
  """
  @type configuration :: %{
          ProgramAssociationTable.program_id_t() => ProgramMapTable.t()
        }

  @type mapping :: %{
          ProgramMapTable.stream_id_t() => {Membrane.Element.Pad.name_t(), integer()}
        }

  @ts_packet_size 188
  @pat 0
  @pmt 2

  defmodule State do
    @moduledoc false
    defstruct queue: <<>>,
              parser: %Parser.State{},
              demands: MapSet.new(),
              work_state: :waiting_pat,
              configuration: %{}

    @type work_state_t :: :waiting_pat | :waiting_pmt | :awaiting_mapping | :working
  end

  def_output_pad :output,
    availability: :on_request,
    caps: :any

  def_input_pad :input, caps: :any, demand_unit: :buffers

  @impl true
  def handle_demand(_pad, _size, _unit, _ctx, %State{work_state: work_state} = state)
      when work_state in [:waiting_pat, :waiting_pmt, :awaiting_mapping] do
    {:ok, state}
  end

  def handle_demand(_pad, size, _unit, _ctx, %State{work_state: :working} = state) do
    {{:ok, demand: {:input, &(&1 + size)}}, state}
  end

  @impl true
  def handle_init(_) do
    {:ok, %State{}}
  end

  @impl true
  def handle_other({:mpeg_ts_mapping, configuration}, _ctx, state) do
    state = %State{state | configuration: configuration, work_state: :working}
    {{:ok, demand: :input}, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, demand: :input}, state}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, %State{work_state: work_state} = state)
      when work_state in [:waiting_pmt, :waiting_pat] do
    %{state | queue: state.queue <> buffer.payload}
    |> handle_startup()
  end

  def handle_process(
        :input,
        buffer,
        _ctx,
        %State{work_state: :awaiting_mapping, queue: q} = state
      ) do
    state = %State{state | queue: q <> buffer.payload}
    {:ok, state}
  end

  def handle_process(:input, buffer, _ctx, %State{work_state: :working} = state) do
    {payloads, queue, parser} = Parser.parse_packets(state.queue <> buffer.payload, state.parser)

    payloads =
      payloads
      |> Enum.group_by(fn {pid, _payload} -> pid end, fn {_pid, payload} -> payload end)

    buffer_actions =
      payloads
      |> Enum.filter(fn {stream_pid, _} -> stream_pid in Map.keys(state.configuration) end)
      |> Enum.map(fn {stream_pid, payloads} ->
        buffers = Enum.map(payloads, fn payload -> %Buffer{payload: payload} end)
        {pad_name, dynamic_id} = state.configuration[stream_pid]
        {:buffer, {{:dynamic, pad_name, dynamic_id}, buffers}}
      end)

    actions = buffer_actions ++ [redemand: {:dynamic, :output, 0}]
    state = %State{state | queue: queue, parser: parser}
    {{:ok, actions}, state}
  end

  defp handle_startup(%State{queue: queue} = state) when byte_size(queue) < @ts_packet_size do
    {{:ok, demand: :input}, state}
  end

  defp handle_startup(state) do
    case Parser.parse_single_packet(state.queue, state.parser) do
      {{:ok, {_pid, table_data}}, {rest, parser_state}} ->
        %State{state | parser: parser_state, queue: rest}
        |> parse_table(table_data)
        |> handle_parse_result()

      {{:error, _reason}, {rest, parser_state}} ->
        %State{state | parser: parser_state, queue: rest}
        |> handle_startup
    end
  end

  defp parse_table(state, table_data) do
    case Membrane.Element.MPEG.TS.Table.parse(table_data) do
      {:ok, {header, data, _crc}} ->
        handle_table(header, data, state)

      {:error, _} = error ->
        {error, state}
    end
  end

  defp handle_table(%Table{table_id: @pat}, data, %State{work_state: :waiting_pat} = state) do
    parser = %{state.parser | known_tables: Map.values(data)}
    state = %State{state | work_state: :waiting_pmt, parser: parser}

    {:ok, state}
  end

  defp handle_table(
         %Table{table_id: @pmt} = table,
         data,
         %State{work_state: :waiting_pmt} = state
       ) do
    configuration = Map.put(state.configuration, table.transport_stream_id, data)
    state = %State{state | configuration: configuration}

    if state.parser.known_tables == [] do
      state = %State{state | work_state: :awaiting_mapping}
      {{:ok, notify: {:mpeg_ts_mapping_req, configuration}}, state}
    else
      {:ok, state}
    end
  end

  defp handle_table(_, _, state) do
    {{:error, :wrong_table}, state}
  end

  # Demands another buffer if queue does not contain enough data
  defp handle_parse_result({:ok, %State{work_state: ws, queue: queue} = state})
       when ws in [:waiting_pat, :waiting_pmt] do
    if queue |> byte_size() < @ts_packet_size do
      {{:ok, demand: :input}, state}
    else
      handle_startup(state)
    end
  end

  defp handle_parse_result({{:error, _reason}, state}), do: handle_startup(state)
  defp handle_parse_result({{:ok, _actions}, _state} = result), do: result
end
