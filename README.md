# Membrane Multimedia Framework: MPEG-TS

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_mpegts_plugin.svg)](https://hex.pm/packages/membrane_mpegts_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_mpegts_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_mpegts_plugin)

This package provides an element that can be used for demuxing MPEG-TS.

It is part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

The package can be installed by adding `membrane_mpegts_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_mpegts_plugin, "~> 0.4.0"}
  ]
end
```

The docs can be found at [HexDocs](https://hexdocs.pm/membrane_mpegts_plugin).

## Abbreviations

PAT - Program Association Table
PMT - Program Mapping Table

## Usage

Demuxer is an element that has one `:input` and variable amount of outputs depending on the stream.
In this particular example we are demuxing a file that contains MPEG1 audio and H264 video.

```elixir
@impl true
def handle_init(path) do
  children = [
    source_file: %File.Source{location: path, chunk_size: 64_000},
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
corresponding pad linked or after receiving `:pads_ready` message. If demuxer receives
`:pads_ready` it will continue its work even though some pads might not be linked.

`prog_map_tables` that is received by pipeline has following format:

```
%{
  program_id => %Membrane.MPEG.TS.ProgramMapTable{
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

  with {:ok, audio_pid} <- first_matching_stream(mapping.streams, :MPEG1_AUDIO),
      {:ok, video_pid} <- first_matching_stream(mapping.streams, :H264) do
    {audio_pid, video_pid}
  end
end

def first_matching_stream(streams, type) do
  streams
  |> Enum.find(fn {_, value} -> value.type == type end)
  |> case do
    nil -> {:error, :no_stream}
    {pid, _stream_spec} -> {:ok, pid}
  end
end
```

## Copyright and License

Copyright 2019, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_mpegts_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_mpegts_plugin)

Licensed under the [Apache License, Version 2.0](https://github.com/membraneframework/membrane_mpegts_plugin/blob/master/LICENSE)
