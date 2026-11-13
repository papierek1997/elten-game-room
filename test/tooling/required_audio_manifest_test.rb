require 'json'
require_relative '../support/assertions'
require_relative '../support/host_source'
require EltenTestHost.file('src/bootstrap.rb')
require EltenTestHost.file('src/eapi/resources.rb')
require EltenTestHost.file('src/eapi/program.rb')
require_relative '../../lib/duck_racing/challenge_audio'
include GameRoomTest::Assertions

root = File.expand_path('../..', __dir__)
standalone = JSON.parse(File.read(File.join(root, 'manifest.json'), encoding: 'UTF-8'))
source = File.binread(File.join(root, '__app.rb'))
embedded = JSON.parse(source.split('=begin Elten3AppInfo', 2).last.split('=end Elten3AppInfo', 2).first)
assert_equal(standalone, embedded, 'Runtime and release manifests disagree')

audio = GameRoomDuckRacing::ChallengeAudio
stimuli = [audio::TONE_ASSET, audio::QUACK_ASSET, audio::SHOT_ASSET,
  audio::COUNTDOWN_ASSET, *audio::MEMORY_ASSETS, *audio::RHYTHM_ASSETS.values,
  'replay', 'buzzer', 'audio_ball_wrong_turn', 'scopa', 'scopa_deal', 'scopa_take',
  'billiards_cue', 'billiards_collision', 'billiards_cushion', 'billiards_pocket',
  'auction_gavel', 'auction_chest', 'auction_call_low', 'auction_call_high'].uniq
available = Dir.glob('*.opus', base: File.join(root, 'Audio')).to_h do |name|
  [File.basename(name, '.opus'), Object.new]
end
checks = 0
{'standalone' => standalone, 'embedded' => embedded}.each do |origin, data|
  # Only native manifest parsing and the real startup guard run here. Assets
  # are opaque tokens: no sound device, application launch or package build.
  runtime = Programs::Runtime.allocate
  runtime.instance_variable_set(:@manifest, Programs::Manifest.new(data, origin))
  runtime.instance_variable_set(:@sound_assets, available.dup)
  assert(runtime.validate_required_assets!, "#{origin}: complete resources were rejected")
  stimuli.each do |name|
    assert(available.key?(name), "Missing current challenge audio file: #{name}")
    runtime.instance_variable_set(:@sound_assets, available.reject { |key, _| key == name })
    assert_equal({'sounds' => [name]}, runtime.missing_required_assets,
      "#{origin}: missing challenge stimulus bypasses the startup guard: #{name}")
    error = assert_raises(Programs::ProgramError) { runtime.validate_required_assets! }
    assert(error.message.include?(name), 'Native missing-resource error lost the asset name')
    checks += 1
  end
  runtime.instance_variable_set(:@sound_assets, available.dup)
  assert(runtime.validate_required_assets!, "#{origin}: guard did not recover after restoring resources")
end
puts "PASS required challenge audio: both native manifests, #{checks} missing-stimulus guards, complete-resource recovery; no playback"
