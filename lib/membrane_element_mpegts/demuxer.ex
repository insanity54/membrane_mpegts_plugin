defmodule Membrane.Element.MpegTS.Demuxer do
  @moduledoc """
  Demuxes MpegTS stream.
  """

  alias __MODULE__.Parser
  alias Membrane.Buffer
  use Membrane.Element.Base.Filter

  def_output_pad :output, caps: :any

  def_input_pad :input, caps: :any, demand_unit: :buffers

  @impl true
  def handle_init(_) do
    {:ok, %{queue: <<>>, parser: Parser.init_state()}}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, _ctx, state) do
    {payloads, queue, parser} = Parser.parse_packets(state.queue <> payload, state.parser)

    {{:ok,
      buffer: {:output, %Buffer{payload: payloads |> Map.get(256, <<>>)}}, redemand: :output},
     %{state | queue: queue, parser: parser}}
  end

  @impl true
  def handle_demand(:output, _size, _unit, _ctx, state) do
    {{:ok, demand: :input}, state}
  end
end
