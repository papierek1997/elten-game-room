require "digest"
require "json"
require "open3"

def assert(value, message)
  raise message unless value
end

def checked_output(*command)
  output, error, status = Open3.capture3(*command, binmode: true)
  raise "Audio validation failed: #{error}" unless status.success?
  output
end

def rms_db(samples)
  power = samples.sum { |sample| sample * sample } / samples.length
  power.positive? ? 10 * Math.log10(power) : -180.0
end

root = File.expand_path("../..", __dir__)
distances = %w[mille_distance_25 mille_distance_50 mille_distance_75 mille_distance_100 mille_distance_200]
car_recordings = distances + ["mille_driving_ace"]
recordings = car_recordings + %w[mille_puncture_proof mille_red_light mille_tire_puncture
  mille_speed_limit mille_end_speed_limit mille_extra_tank mille_end_counterflow]
hashes = []
recordings.each do |name|
  path = File.join(root, "Audio", "#{name}.opus")
  streams = JSON.parse(checked_output("ffprobe", "-v", "error", "-show_streams", "-of", "json", path)).fetch("streams")
  assert(streams.length == 1, "#{name}: unexpected stream inventory")
  stream = streams.first
  assert(stream.fetch("codec_name") == "opus" && stream.fetch("sample_rate").to_i == 48_000,
    "#{name}: not 48 kHz Opus")
  channels = stream.fetch("channels")
  samples = checked_output("ffmpeg", "-v", "error", "-nostdin", "-xerror", "-err_detect", "explode",
    "-i", path, "-map", "0:a:0", "-ar", "48000", "-f", "f32le", "-").unpack("e*")
  assert(!samples.empty? && samples.length % channels == 0 && samples.all?(&:finite?),
    "#{name}: invalid decoded samples")
  duration = samples.length.fdiv(channels * 48_000)
  if name == "mille_extra_tank"
    assert(samples.length / channels == 390_390, "#{name}: incomplete fuel-cap recording")
  else
    assert(duration.between?(0.5, 8.0), "#{name}: unsuitable duration #{duration}")
  end
  window = 2400 * channels
  peak_window = samples.each_slice(window).select { |block| block.length == window }.map { |block| rms_db(block) }.max
  assert(peak_window > -40, "#{name}: no meaningful audible event")
  assert(peak_window - rms_db(samples.first(window)) >= 20, "#{name}: abrupt beginning")
  assert(peak_window - rms_db(samples.last(window)) >= 20, "#{name}: abrupt ending")
  hashes << Digest::SHA256.hexdigest(samples.pack("e*"))
end
assert(hashes.uniq.length == recordings.length, "Card recordings are not distinct")
puts "PASS #{recordings.length} complete distinct 48 kHz Opus cues: quiet boundaries, meaningful content and bounded durations"
