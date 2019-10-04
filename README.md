# Membrane Multimedia Framework: MPEG-TS

This package provides element that can be used for demuxing MPEG-TS.

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

## Abbrevations

PAT - Program Association Table
PMT - Program Mapping Table

## Example Usage

Demuxer is an elemant that has one `:input` and variable amount of outputs depending on the stream.
In this particular example we are demuxing a file that contains MPEG audio and H264 video.

```elixir
  @impl true
  def handle_init(path) do
    children = [
      file: %File.Source{location: path, chunk_size: 64000},
      demuxer: MPEG.TS.Demuxer,
      parser: %H264.Parser{framerate: {24, 1}},
      decoder: H264.Decoder,
      sdl: SDL.Player,
      mad: Mad.Decoder,
      converter: %SWResample.Converter{
        output_caps: %Raw{channels: 2, format: :s16le, sample_rate: 48_000}
      },
      portaudio: PortAudio.Sink
    ]

    links = %{
      {:file, :output} => {:demuxer, :input},
      {:demuxer, :output, 1} => {:parser, :input},
      {:demuxer, :output, 0} => {:mad, :input},
      {:parser, :output} => {:decoder, :input},
      {:decoder, :output} => {:sdl, :input},
      {:mad, :output} => {:converter, :input},
      {:converter, :output} => {:portaudio, :input}
    }

    {{:ok,
      spec: %Spec{
        children: children,
        links: links,
        stream_sync: :sinks
      }}, %{}}
  end
```

Upon successful parsing of MPEG Transport stream specific information, demuxer will notify
pipeline. When pipeline receives `{:mpeg_ts_mapping_req, configuration}` message it will need to respond
with configuration, that maps streams to pads.

```elixir
  @impl true
  def handle_notification({:mpeg_ts_mapping_req, mapping}, from, state) do
    {video_pid, audio_pid} = parse_maping(mapping)
    mapping = %{{:output, 1} => video_pid, {:output, 0} => audio_pid}
    message = {:config_demuxer, mapping}
    {{:ok, forward: {:demuxer, message}}, state}
  end
```

## Copyright and License

Copyright 2019, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane-element-mpegts)

[![Software Mansion](https://membraneframework.github.io/static/logo/swm_logo_readme.png)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane-element-mpegts)

Licensed under the [Apache License, Version 2.0](LICENSE)
