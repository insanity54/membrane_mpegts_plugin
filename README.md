# Membrane Multimedia Framework: MPEG-TS

This package provides an element that can be used for demuxing MPEG-TS.

It is part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

The package can be installed by adding `membrane_element_mpegts` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_element_mpegts, "~> 0.1.0"}
  ]
end
```

The docs can be found at [HexDocs](https://hexdocs.pm/membrane_element_mpegts).

## Abbreviations

PAT - Program Association Table
PMT - Program Mapping Table

## Usage

Demuxer is an element that has one `:input` and variable amount of outputs depending on the stream.
In this particular example we are demuxing a file that contains MPEG audio and H264 video.

```elixir
@impl true
def handle_init(path) do
  children = [
    source_file: %File.Source{location: path, chunk_size: 64000},
    demuxer: MPEG.TS.Demuxer,
    video_parser: %H264.Parser{framerate: {24, 1}},
    video_decoder: H264.Decoder,
    player: SDL.Player,
    audio_decoder: Mad.Decoder,
    audio_converter: %SWResample.Converter{
      output_caps: %Raw{channels: 2, format: :s16le, sample_rate: 48_000}
    },
    portaudio: PortAudio.Sink
  ]

  links = [
    link(:source_file) |> to(:demuxer),
    link(:demuxer) |> via_out(Pad.ref(:output, 256)) |> to(:video_parser),
    link(:demuxer) |> via_out(Pad.ref(:output, 257)) |> to(:audio_decoder),
    link(:video_parser) |> to(:video_decoder),
    link(:video_decoder) |> to(:player),
    link(:audio_decoder) |> to(:audio_converter),
    link(:audio_converter) |> to(:portaudio)
  ]

  spec = %Spec{
    children: children,
    links: links,
    stream_sync: :sinks
  }

  {{:ok, spec: spec}, %{}}
end
```

Upon successful parsing of MPEG Transport stream specific information, demuxer will notify
its parent (usally a pipeline). When the parent receives `{:mpeg_ts_stream_info, prog_map_tables}` message it will need to
link the demuxer outputs. The demuxer will continue its work when either every stream will have its
corresponding pad linked or after receiving `:pads_ready` message.

`prog_map_tables` that is received by pipeline has following format:

```
%{
  program_id => %Membrane.Element.MPEG.TS.ProgramMapTable{
    streams: %{
      packet_identifier => %{
        type: atom,
        type_id: 0..255
      }
    }
  }
}
```

So, far example, if we wanted to have as simple behaviour as use first stream with matching type
we would do it like this:

```elixir
@impl true
def handle_notification({:mpeg_ts_stream_info, pmt}, _from, state) do
  {audio_pid, video_pid} = parse_mapping(pmt)

  children = [
    audio: An.Audio.Element,
    video: A.Video.Element
  ]

  links = [
    link(:demuxer) |> via_out(Pad.ref(:output, audio_pid)) |> to(:audio),
    link(:demuxer) |> via_out(Pad.ref(:output, video_pid)) |> to(:video)
  ]

  spec = %Spec{
    children: children,
    links: links,
  }

  {{:ok, spec: spec}, state}
end

defp parse_mapping(mapping) do
  mapping = mapping[1]

  with {:ok, audio_pid} <- first_matching_stream(mapping.streams, :mpeg_audio),
      {:ok, video_pid} <- first_matching_stream(mapping.streams, :h264) do
    {audio_pid, video_pid}
  end
end

defp first_matching_stream(streams, type) do
  streams
  |> Enum.filter(fn {_, value} -> value.stream_type == type end)
  |> case do
    [{pid, _}] -> {:ok, pid}
    _ -> {:error, :no_stream}
  end
end
```

## Copyright and License

Copyright 2019, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane-element-mpegts)

[![Software Mansion](https://membraneframework.github.io/static/logo/swm_logo_readme.png)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane-element-mpegts)

Licensed under the [Apache License, Version 2.0](LICENSE)
