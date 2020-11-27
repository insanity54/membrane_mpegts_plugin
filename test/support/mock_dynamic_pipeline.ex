defmodule Membrane.MPEG.TS.Support.MockDynamicPipeline do
  @moduledoc false
  use Membrane.Pipeline

  alias Membrane.File

  @impl true
  def handle_init(
        %{
          input_path: input_path
        } = options
      ) do
    elements = [
      in: %File.Source{location: input_path},
      demuxer: Membrane.MPEG.TS.Demuxer
    ]

    links = [
      link(:in) |> to(:demuxer)
    ]

    spec = %ParentSpec{
      children: elements,
      links: links
    }

    {{:ok, spec: spec}, options}
  end

  def handle_notification({:mpeg_ts_stream_info, _maping}, _from, state) do
    elements = [
      audio_out: %File.Sink{location: state.audio_out},
      video_out: %File.Sink{location: state.video_out}
    ]

    links = [
      link(:demuxer) |> via_out(Pad.ref(:output, 256)) |> to(:video_out),
      link(:demuxer) |> via_out(Pad.ref(:output, 257)) |> to(:audio_out)
    ]

    spec = %ParentSpec{
      children: elements,
      links: links
    }

    {{:ok, spec: spec}, state}
  end

  def handle_notification(_notification, _from, state), do: {:ok, state}
end
