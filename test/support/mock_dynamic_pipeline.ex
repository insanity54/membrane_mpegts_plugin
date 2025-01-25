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
    # elements = [
    #   in: %File.Source{location: input_path},
    #   demuxer: Membrane.MPEG.TS.Demuxer
    # ]

    # links = [
    #   link(:in) |> to(:demuxer)
    # ]

    # spec = %ParentSpec{
    #   children: elements,
    #   links: links
    # }
    spec = [
      child(:in, %File.Source{location: input_path})
      |> child(:demuxer, Membrane.MPEG.TS.Demuxer)
    ]


    {[spec: spec], options}

  end

  def handle_child_notification({:mpeg_ts_stream_info, _maping}, _from, state) do
    # elements = [
    #   audio_out: %File.Sink{location: state.audio_out},
    #   video_out: %File.Sink{location: state.video_out}
    # ]

    # links = [
    #   link(:demuxer) |> via_out(Pad.ref(:output, 256)) |> to(:video_out),
    #   link(:demuxer) |> via_out(Pad.ref(:output, 257)) |> to(:audio_out)
    # ]


    # spec = [
    #   child(%File.Source{location: "source"})
    #   |> child(:tee, Tee.Parallel),
    #   get_child(:tee) |> via_out(Pad.ref(:output, 1)) |> child(%File.Sink{location: "target1"}),
    #   get_child(:tee) |> via_out(Pad.ref(:output, 2)) |> child(%File.Sink{location: "target2"}),
    #   get_child(:tee) |> via_out(Pad.ref(:output, 3)) |> child(%File.Sink{location: "target3"})
    # ]

    spec = [
      get_child(:demuxer)
      |> via_out(:output, pad_ref: Pad.ref(:output, 256))
      |> via_in(:video_out)
      |> child(:video_out),
      get_child(:demuxer)
      |> via_out(:output, pad_ref: Pad.ref(:output, 257))
      |> via_in(:audio_out)
      |> child(:audio_out)
    ]

    # spec = %ChildrenSpec{
    #   children: elements,
    #   links: links
    # }




    {[spec: spec], state}
  end

  def handle_child_notification(_notification, _from, state), do: {[], state}
end
