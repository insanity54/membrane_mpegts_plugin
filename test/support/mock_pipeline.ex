defmodule Membrane.Element.MPEG.TS.Support.MockPipeline do
  @moduledoc false
  use Membrane.Pipeline
  alias Membrane.Pipeline.Spec

  @impl true
  def handle_init(%{
        inptu_path: input_path,
        audio_out: audio_out,
        video_out: video_out
      }) do
    elements = [
      in: %Membrane.Element.File.Source{location: input_path},
      demuxer: Membrane.Element.MPEG.TS.Demuxer,
      audio_out: %Membrane.Element.File.Sink{location: audio_out},
      video_out: %Membrane.Element.File.Sink{location: video_out}
    ]

    links = %{
      {:in, :output} => {:demuxer, :input},
      {:demuxer, :output, 1} => {:video_out, :input},
      {:demuxer, :output, 0} => {:audio_out, :input}
    }

    spec = %Spec{
      children: elements,
      links: links
    }

    {{:ok, spec: spec}, %{}}
  end

  def handle_notification({:mpeg_ts_mapping_req, _maping}, _from, state) do
    mapping = %{256 => {:output, 1}, 257 => {:output, 0}}
    message = {:mpeg_ts_mapping, mapping}
    {{:ok, forward: {:demuxer, message}}, state}
  end

  def handle_notification(_notification, _from, state), do: {:ok, state}
end
