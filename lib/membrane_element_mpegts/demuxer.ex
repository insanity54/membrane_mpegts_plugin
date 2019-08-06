defmodule Membrane.Element.MpegTS.Demuxer do
  @moduledoc """
  Demuxes MpegTS stream.
  """

  alias __MODULE__.Parser
  alias Membrane.Buffer
  use Membrane.Element.Base.Filter

  def_output_pad :out_video, caps: :any
  def_output_pad :out_audio, caps: :any

  def_input_pad :input, caps: :any, demand_unit: :buffers

  @impl true
  def handle_init(_) do
    {:ok, %{queue: <<>>, parser: Parser.init_state(), demands: MapSet.new()}}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, _ctx, state) do
    {payloads, queue, parser} = Parser.parse_packets(state.queue <> payload, state.parser)

    buffers =
      payloads
      |> Enum.flat_map(fn
        {256, payload} -> [buffer: {:out_video, %Buffer{payload: payload}}]
        {257, payload} -> [buffer: {:out_audio, %Buffer{payload: payload}}]
        _ -> []
      end)

    {{:ok, buffers ++ [redemand: [:out_audio, :out_video]]},
     %{state | queue: queue, parser: parser}}
  end

  @impl true
  def handle_demand(output, _size, _unit, _ctx, state) do
    demands = state.demands |> MapSet.put(output)

    if MapSet.size(demands) == 2 do
      {{:ok, demand: :input}, %{state | demands: MapSet.new()}}
    else
      {:ok, %{state | demands: demands}}
    end
  end
end
