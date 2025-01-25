defmodule Membrane.MPEG.TS.Support.MockStaticPipeline do
  @moduledoc false
  use Membrane.Pipeline

  alias Membrane.File
  require Membrane.Logger

  @impl true
  def handle_init(
    %{
      input_path: input_path,
      audio_out: audio_out,
      video_out: video_out
    }) do
    # elements = [
    #   in: %File.Source{location: input_path},
    #   demuxer: Membrane.MPEG.TS.Demuxer,
    #   audio_out: %File.Sink{location: audio_out},
    #   video_out: %File.Sink{location: video_out}
    # ]

    # links = [
    #   link(:in) |> to(:demuxer),
    #   link(:demuxer) |> via_out(Pad.ref(:output, 256)) |> to(:video_out),
    #   link(:demuxer) |> via_out(Pad.ref(:output, 257)) |> to(:audio_out)
    # ]

    # spec = %ParentSpec{
    #   children: elements,
    #   links: links
    # }

    spec = [
      child(:in, %File.Source{location: input_path}),
      child(:demuxer, Membrane.MPEG.TS.Demuxer),
      get_child(:in)
      |> child(:demuxer),
      get_child(:demuxer)
      |> via_out(Pad.ref(:output, 256))
      |> child(:video_out, %File.Sink{location: video_out}),
      get_child(:demuxer)
      |> via_out(Pad.ref(:output, 257))
      |> child(:audio_out, %File.Sink{location: audio_out})
    ]

    {[spec: spec], %{}}
  end

  def handle_child_notification({:mpeg_ts_stream_info, _mapping}, _from, state) do
    Membrane.Logger.warning("SUCCESS! handle_child_notification with :mpeg_ts_stream_info has fired!")
    {[forward: {:demuxer, :pads_ready}], state}
  end

  # @impl true
  # def handle_child_notification({:track_playable, :video}, _element, _ctx, state) do
  #   {[], state}
  # end



  def handle_child_notification(_notification, _from, state), do: {[], state}
end
