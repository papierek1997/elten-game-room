# Explicit audio authoring, never part of a build or the game loop.
require_relative "encode_audio"

root = File.expand_path("..", __dir__)
source = File.join(root, "audio", "draw2.opus")
ffmpeg, ffprobe = ARGV
ffmpeg ||= "ffmpeg"
ffprobe ||= "ffprobe"
probe = GameRoomAudioEncoding.probe(source, ffprobe: ffprobe)
rate = probe.fetch("streams").find { |stream| stream["codec_type"] == "audio" }.fetch("sample_rate").to_i
{"bouillabaisse_rank"=>-3, "bouillabaisse_card"=>-6}.each do |name, semitones|
  target = File.join(root, "audio", "#{name}.opus")
  raise "Refusing to overwrite #{target}" if File.exist?(target)
  factor = 2.0 ** (semitones / 12.0)
  arguments = GameRoomAudioEncoding.arguments(source, target)
  arguments.insert(arguments.index("-c:a"), "-af", "asetrate=#{(rate * factor).round},aresample=48000,atempo=#{1.0 / factor}")
  output, error, status = Open3.capture3(ffmpeg, *arguments)
  raise "Cannot author #{name}: #{error} #{output}" unless status.success?
  puts "#{name}: #{semitones} semitones; source draw2, duration retained, 144k VBR Opus"
end
