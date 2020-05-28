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

## Example Usage

Demuxer is an element that has one `:input` and variable amount of outputs depending on the stream.
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
pipeline. When pipeline receives `{:mpeg_ts_mapping_req, prog_map_tables}` message it will need to
respond with mapping, that maps streams to pads.

`prog_map_tables` that is received by pipeline has following format:

```
%{
  program_id => %Membrane.Element.MPEG.TS.ProgramMapTable{
    streams: %{
      stream_pid => %{
        stream_type: atom,
        stream_type_id: 0..255
      }
    }
  }
}
```

So, far example, if we wanted to have as simple behaviour as use first stream with matching type
we would do it like this:

```elixir
@impl true
def handle_notification({:mpeg_ts_mapping_req, prog_map_tables}, from, state) do
  {video_pid, audio_pid} = parse_maping(prog_map_tables)
  mapping = %{{:output, 1} => video_pid, {:output, 0} => audio_pid}
  message = {:config_demuxer, mapping}
  {{:ok, forward: {:demuxer, message}}, state}
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
  |> Enum.filter(fn {_, value} -> match?(%{stream_type: ^type}, value) end)
  |> case do
    [{pid, _}] -> {:ok, pid}
    _ -> {:error, :no_stream}
  end
end
```

Upon successful parsing of MPEG Transport stream specific information, demuxer will notify
pipeline. When pipeline receives `{:mpeg_ts_mapping_req, prog_map_tables}` message it will need to
respond with the mapping, that maps streams to pads.

`prog_map_tables` that is received by pipeline has the following format:

```
%{
  program_id => %Membrane.Element.MPEG.TS.ProgramMapTable{
    streams: %{
      stream_pid => %{
        stream_type: atom,
        stream_type_id: 0..255
      }
    }
  }
}
```

So, for example, if we wanted to have as simple behavior as using the first stream with a matching
type we would do it like this:

```elixir
@impl true
def handle_notification({:mpeg_ts_mapping_req, prog_map_tables}, from, state) do
  {video_pid, audio_pid} = parse_maping(prog_map_tables)
  mapping = %{{:output, 1} => video_pid, {:output, 0} => audio_pid}
  message = {:config_demuxer, mapping}
  {{:ok, forward: {:demuxer, message}}, state}
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
