defmodule Membrane.Element.MpegTS.ProgramMapTable.StreamTypeAssigment do
  def parse(0x03), do: :mpeg_audio
  def parse(0x1B), do: :h264
end
