# Explicit authoring only; never run during a build or in a game frame.
require_relative 'encode_audio'

module GameRoomFiveDiceAudioAuthoring
  module_function

  def author(bonus, doubled, record, ffmpeg: 'ffmpeg', ffprobe: 'ffprobe')
    root = File.expand_path('..', __dir__)
    audio = File.join(root, 'Audio')
    sources = {bonus:File.realpath(bonus), doubled:File.realpath(doubled), record:File.realpath(record)}
    targets = sources.keys.map { |effect| File.join(audio, "five_dice_#{effect}.opus") }
    targets += (1..6).flat_map do |column|
      %i[bonus doubled].map { |effect| File.join(audio, "kosciane_column_#{column}_#{effect}.opus") }
    end
    raise 'Refusing to overwrite an authored recording' if targets.any? { |path| File.exist?(path) }
    sources.each do |effect, source|
      GameRoomAudioEncoding.encode(source, File.join(audio, "five_dice_#{effect}.opus"), ffmpeg:ffmpeg, ffprobe:ffprobe)
    end
    (1..6).each do |column|
      prefix = File.join(audio, "kosciane_column_#{column}.opus")
      %i[bonus doubled].each do |effect|
        source = sources.fetch(effect)
        channels = [prefix, source].map do |path|
          GameRoomAudioEncoding.probe(path, ffprobe:ffprobe).fetch('streams').find { |stream| stream['codec_type'] == 'audio' }.fetch('channels')
        end
        raise 'Column cue and feedback must have matching channels' unless channels.uniq.one?
        Tempfile.create(['five-dice-', '.wav']) do |wave|
          wave.close
          # Decode the calibrated column prefix and concatenate the entire new
          # recording. No old success effect, trimming, gain or normalization.
          _output, error, status = Open3.capture3(ffmpeg, '-v', 'error', '-nostdin', '-y',
            '-i', prefix, '-i', source, '-filter_complex',
            '[0:a]aresample=48000[p];[1:a]aresample=48000[s];[p][s]concat=n=2:v=0:a=1[out]',
            '-map', '[out]', '-c:a', 'pcm_f32le', wave.path)
          raise "Cannot combine column feedback: #{error}" unless status.success?
          GameRoomAudioEncoding.encode(wave.path, File.join(audio, "kosciane_column_#{column}_#{effect}.opus"),
            ffmpeg:ffmpeg, ffprobe:ffprobe)
        end
      end
    end
    targets
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: ruby tools/author-five-dice-feedback.rb BONUS DOUBLED RECORD [FFMPEG FFPROBE]' unless (3..5).cover?(ARGV.length)
  bonus, doubled, record, ffmpeg, ffprobe = ARGV
  targets = GameRoomFiveDiceAudioAuthoring.author(bonus, doubled, record,
    ffmpeg:ffmpeg || 'ffmpeg', ffprobe:ffprobe || 'ffprobe')
  puts "Authored #{targets.length} recordings; existing assets preserved"
end
