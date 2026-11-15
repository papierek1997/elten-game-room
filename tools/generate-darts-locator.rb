# encoding: UTF-8
# Reproducible, gently pulsing Darts locator. This authoring tool creates PCM
# directly and delegates only the final packaging conversion to the project's
# standard Opus encoder; it does not load or call ELTEN's playback engine.
require 'tmpdir'
require_relative 'encode_audio'

SAMPLE_RATE = 48_000
DURATION = 1.0
VARIANTS = {
  'round' => {fundamental: 280.0, pulse: 3.0, floor: 0.62, amplitudes: [0.18, 0.035, 0.010]},
  'clear' => {fundamental: 360.0, pulse: 4.0, floor: 0.68, amplitudes: [0.185, 0.028, 0.007]},
  'bright' => {fundamental: 440.0, pulse: 5.0, floor: 0.72, amplitudes: [0.19, 0.024, 0.006]}
}.freeze

targets = VARIANTS.to_h do |name, _spec|
  [name, File.expand_path("../Audio/darts_locator_#{name}.opus", __dir__)]
end
existing = targets.values.select { |path| File.exist?(path) }
raise "Refusing to overwrite #{existing.join(', ')}" unless existing.empty?

frame_count = (SAMPLE_RATE * DURATION).round
format = [1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16].pack('vvVVvv')

Dir.mktmpdir('gr-darts-locator-') do |directory|
  VARIANTS.each do |name, spec|
    samples = Array.new(frame_count) do |index|
      time = index.to_f / SAMPLE_RATE
      phase = 2.0 * Math::PI * spec[:fundamental] * time
      pulse = spec[:floor] + (1.0 - spec[:floor]) *
        (0.5 - 0.5 * Math.cos(2.0 * Math::PI * spec[:pulse] * time))
      value = spec[:amplitudes].each_with_index.sum do |amplitude, harmonic|
        amplitude * Math.sin(phase * (harmonic + 1))
      end
      (value * pulse * 32_767).round.clamp(-32_768, 32_767)
    end
    pcm = samples.pack('s<*')
    wave = 'RIFF'.b + [36 + pcm.bytesize].pack('V') + 'WAVEfmt '.b + [16].pack('V') + format +
      'data'.b + [pcm.bytesize].pack('V') + pcm
    source = File.join(directory, "darts_locator_#{name}.wav")
    File.binwrite(source, wave)
    GameRoomAudioEncoding.encode(source, targets.fetch(name),
      ffmpeg: ARGV[0] || 'ffmpeg', ffprobe: ARGV[1] || 'ffprobe')
  end
end

puts 'Generated three seamless one-second mono Darts locators at 48 kHz and 144 kb/s VBR Opus.'
