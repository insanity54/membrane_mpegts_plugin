defmodule Membrane.MPEG.TS.Demuxer do
  @moduledoc """
  Demuxes MPEG TS stream.

  After transition into playing state, this element will wait for
  [Program Association Table](https://en.wikipedia.org/wiki/MPEG_transport_stream#PAT) and
  [Program Mapping Table](https://en.wikipedia.org/wiki/MPEG_transport_stream#PMT).
  Upon succesfful parsing of those tables it will send a message to the pipeline in format
  `{:mpeg_ts_stream_info, configuration}`, where configuration contains data read from tables.

  Configuration sent by element to pipeline should have following shape
  ```
  %{
    program_id => %Membrane.MPEG.TS.ProgramMapTable{
      pcr_pid: 256,
      program_info: [],
      streams: %{
        256 => %{stream_type: :H264, stream_type_id: 27},
        257 => %{stream_type: :MPEG1_AUDIO, stream_type_id: 3}
      }
    }
  }
  ```
  """
  use Membrane.Filter

  alias __MODULE__.Parser
  alias Membrane.Buffer
  alias Membrane.MPEG.TS.Table
  alias Membrane.MPEG.TS.{ProgramAssociationTable, ProgramMapTable}

  @typedoc """
  This types represents datae structure that is sent by this element to pipeline.
  """
  @type configuration :: %{
          ProgramAssociationTable.program_id_t() => ProgramMapTable.t()
        }

  @ts_packet_size 188
  @pat 0
  @pmt 2

  defmodule State do
    @moduledoc false

    alias Membrane.MPEG.TS.Demuxer

    defstruct data_queue: <<>>,
              parser: %Parser.State{},
              work_state: :waiting_pat,
              configuration: %{}

    @type work_state_t :: :waiting_pat | :waiting_pmt | :awaiting_linking | :working

    @type t :: %__MODULE__{
            data_queue: binary(),
            parser: Parser.State.t(),
            work_state: work_state_t(),
            configuration: Demuxer.configuration()
          }
  end

  def_output_pad :output,
    availability: :on_request,
    accepted_format: _any

  def_input_pad :input,
    accepted_format: _any

  @impl true
  def handle_demand(_pad, _size, _unit, _ctx, %State{work_state: work_state} = state)
      when work_state in [:waiting_pat, :waiting_pmt, :awaiting_linking] do
    {:ok, state}
  end

  def handle_demand(_pad, _size, unit, ctx, %State{work_state: :working} = state) do
    standarized_new_demand = standarize_demand(ctx.incoming_demand, unit)
    {{:ok, demand: {:input, &(&1 + standarized_new_demand)}}, state}
  end

  @impl true
  def handle_init(_) do
    {:ok, %State{}}
  end

  @impl true
  def handle_parent_notification(:pads_ready, _context, %State{work_state: :working} = state),
    do: {[], state}

  @impl true
  def handle_parent_notification(:pads_ready, ctx, %State{work_state: :awaiting_linking} = state) do
    state = %State{state | work_state: :working}
    {{:ok, consolidate_demands(ctx)}, state}
  end

  defp all_pads_added?(configuration, ctx) do
    pad_names =
      ctx.pads
      |> Map.keys()
      |> Enum.filter(&(Pad.name_by_ref(&1) == :output))

    stream_ids =
      configuration
      |> Enum.flat_map(fn {_id, program_table} -> Map.keys(program_table.streams) end)

    Enum.all?(
      stream_ids,
      &Enum.any?(pad_names, fn Pad.ref(:output, id) -> id == &1 end)
    )
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[demand: :input], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %State{work_state: work_state} = state)
      when work_state in [:waiting_pmt, :waiting_pat] do
    %{state | data_queue: state.data_queue <> buffer.payload}
    |> handle_startup()
  end

  def handle_buffer(
        :input,
        buffer,
        _ctx,
        %State{work_state: :awaiting_linking, data_queue: q} = state
      ) do
    state = %State{state | data_queue: q <> buffer.payload}
    {:ok, state}
  end

  def handle_buffer(:input, buffer, ctx, %State{work_state: :working} = state) do
    {payloads, data_queue, parser} =
      Parser.parse_packets(state.data_queue <> buffer.payload, state.parser)

    buffer_actions =
      payloads
      |> Enum.group_by(&Bunch.key/1, &Bunch.value/1)
      # TODO What about ignoring streams
      |> Enum.filter(fn {stream_pid, _} -> Pad.ref(:output, stream_pid) in Map.keys(ctx.pads) end)
      |> Enum.map(fn {stream_pid, payloads} ->
        buffers = Enum.map(payloads, fn payload -> %Buffer{payload: payload} end)
        destination_pad = Pad.ref(:output, stream_pid)
        {:buffer, {destination_pad, buffers}}
      end)

    actions = buffer_actions ++ redemand_all_output_pads(ctx)
    state = %State{state | data_queue: data_queue, parser: parser}
    {{:ok, actions}, state}
  end

  defp redemand_all_output_pads(ctx) do
    out_pads =
      ctx.pads
      |> Map.keys()
      |> Enum.filter(&(Pad.name_by_ref(&1) == :output))

    [redemand: out_pads]
  end

  # Pad added after receving tables
  @impl true
  def handle_pad_added(Pad.ref(:output, _id), ctx, %State{work_state: :awaiting_linking} = state) do
    if all_pads_added?(state.configuration, ctx) do
      state = %State{state | work_state: :working}
      {{:ok, consolidate_demands(ctx)}, state}
    else
      {:ok, state}
    end
  end

  # Pad added during linking
  @impl true
  def handle_pad_added(_pad, _ctx, %State{work_state: work_state} = state)
      when work_state in [:waiting_pat, :waiting_pmt] do
    {:ok, state}
  end

  # TODO: remove when issue in core with handle pad added is resolved
  # issue https://github.com/membraneframework/membrane-core/issues/258
  @impl true
  def handle_pad_added(_pad, _ctx, state) do
    {:ok, state}
  end

  defp handle_startup(%State{data_queue: data_queue} = state)
       when byte_size(data_queue) < @ts_packet_size do
    {{:ok, demand: :input}, state}
  end

  defp handle_startup(state) do
    case Parser.parse_single_packet(state.data_queue, state.parser) do
      {{:ok, {_pid, table_data}}, {rest, parser_state}} ->
        %State{state | parser: parser_state, data_queue: rest}
        |> parse_table(table_data)
        |> handle_parse_result()

      {{:error, _reason}, {rest, parser_state}} ->
        %State{state | parser: parser_state, data_queue: rest}
        |> handle_startup
    end
  end

  defp parse_table(state, table_data) do
    case Membrane.MPEG.TS.Table.parse(table_data) do
      {:ok, {header, data, _crc}} ->
        handle_table(header, data, state)

      {:error, _} = error ->
        {error, state}
    end
  end

  # Received PAT
  defp handle_table(%Table{table_id: @pat}, data, %State{work_state: :waiting_pat} = state) do
    parser = %{state.parser | known_tables: Map.values(data)}
    state = %State{state | work_state: :waiting_pmt, parser: parser}

    {:ok, state}
  end

  # Received one of the PMTs
  defp handle_table(
         %Table{table_id: @pmt} = table,
         data,
         %State{work_state: :waiting_pmt} = state
       ) do
    configuration = Map.put(state.configuration, table.transport_stream_id, data)
    state = %State{state | configuration: configuration}

    if state.parser.known_tables == [] do
      state = %State{state | work_state: :awaiting_linking, configuration: configuration}
      {{:ok, notify: {:mpeg_ts_stream_info, configuration}}, state}
    else
      {:ok, state}
    end
  end

  defp handle_table(_, _, state) do
    {{:error, :wrong_table}, state}
  end

  # Demands another buffer if data_queue does not contain enough data
  defp handle_parse_result({:ok, %State{work_state: ws, data_queue: data_queue} = state})
       when ws in [:waiting_pat, :waiting_pmt] do
    if data_queue |> byte_size() < @ts_packet_size do
      {{:ok, demand: :input}, state}
    else
      handle_startup(state)
    end
  end

  defp handle_parse_result({{:error, _reason}, state}), do: handle_startup(state)
  defp handle_parse_result({{:ok, _actions}, _state} = result), do: result

  defp consolidate_demands(ctx) do
    demand_size =
      ctx.pads
      |> Bunch.KVEnum.filter_by_keys(&(Pad.name_by_ref(&1) == :output))
      |> Enum.reduce(0, fn {_pad_ref, pad_data}, acc ->
        acc + standarize_demand(pad_data.demand, pad_data.other_demand_unit)
      end)

    [demand: {:input, demand_size}]
  end

  defp standarize_demand(size, :buffers), do: size

  defp standarize_demand(size, :bytes) do
    (size / 188) |> ceil()
  end
end
