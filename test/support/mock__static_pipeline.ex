defmodule Membrane.Element.MPEG.TS.Support.MockStaticPipeline do
  @moduledoc false
  use Membrane.Pipeline

  @impl true
  def handle_init(%{
        input_path: input_path,
        audio_out: audio_out,
        video_out: video_out
      }) do
    elements = [
      in: %Membrane.Element.File.Source{location: input_path},
      demuxer: Membrane.Element.MPEG.TS.Demuxer,
      audio_out: %Membrane.Element.File.Sink{location: audio_out},
      video_out: %Membrane.Element.File.Sink{location: video_out}
    ]

    links = [
      link(:in) |> to(:demuxer),
      link(:demuxer) |> via_out(Pad.ref(:output, 256)) |> to(:video_out),
      link(:demuxer) |> via_out(Pad.ref(:output, 257)) |> to(:audio_out)
    ]

    spec = %ParentSpec{
      children: elements,
      links: links
    }

    {{:ok, spec: spec}, %{}}
  end

  def handle_notification({:mpeg_ts_stream_info, _maping}, _from, state) do
    {{:ok, forward: {:demuxer, :pads_ready}}, state}
  end

  def handle_notification(_notification, _from, state), do: {:ok, state}
end
