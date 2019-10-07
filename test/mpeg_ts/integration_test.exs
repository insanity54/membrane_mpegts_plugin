defmodule Membrane.Element.MPEG.TS.IntegrationTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Testing.Pipeline

  @input_path "test/support/all_packets.ts"
  @reference_audio "test/support/reference_audio.ts"
  @reference_video "test/support/reference_video.ts"
  @audio_out "/tmp/audio"
  @video_out "/tmp/video"

  test "Demuxer splits incoming stream into elementary streams" do
    options = %Pipeline.Options{
      module: Membrane.Element.MPEG.TS.Support.MockPipeline,
      custom_args: %{
        input_path: @input_path,
        audio_out: @audio_out,
        video_out: @video_out
      }
    }

    {:ok, pipeline} = Pipeline.start_link(options)
    Pipeline.play(pipeline)
    assert_end_of_stream(pipeline, :video_out)
    assert_end_of_stream(pipeline, :audio_out)
    assert_files_equal(@reference_audio, @audio_out)
    assert_files_equal(@reference_video, @video_out)
  end

  defp assert_files_equal(file_a, file_b) do
    assert {:ok, a} = File.read(file_a)
    assert {:ok, b} = File.read(file_b)
    assert a == b
  end
end
