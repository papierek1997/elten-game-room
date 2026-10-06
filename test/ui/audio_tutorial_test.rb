require_relative "../support/audio_tutorial"

game = GameRoomGames::AudioBall.new
assert(game.respond_to?(:audio_tutorial_entries), 'Games cannot provide a reusable audio tutorial')
entries = game.audio_tutorial_entries
assert(entries.map(&:asset) == %w[audio_ball_up audio_ball_left audio_ball_down audio_ball_prepare audio_ball_stopped],
  'Audio Ball tutorial does not cover its three shots, preparation and stopping in order')
assert(entries.map(&:label) == ['Ball sound: Up arrow or W', 'Ball sound: Left arrow or D',
  'Ball sound: Down arrow or S', 'Preparing the ball: Right arrow or A',
  'Ball stopped after a successful defence'], 'Tutorial labels do not explain the controls')
entries.each do |entry|
  assert(entry.label.encoding == Encoding::UTF_8, 'Tutorial label is not safe for native controls')
  assert(File.file?(File.expand_path("../../Audio/#{entry.asset}.opus", __dir__)), 'Tutorial references a missing sound')
end
assert(GameRoomGames::Makao.new.audio_tutorial_entries.empty?, 'A game without tutorial sounds gained a tutorial')

program = TutorialProgram.new
Form.tutorial_driver = lambda do |form|
  assert(form.fields.length == 1 && form.fields.first.is_a?(ListBox), 'Tutorial opened extra fields or a welcome dialog')
  list = form.fields.first
  assert(list.options == entries.map(&:label) && list.index == 0, 'Tutorial does not start on the first sound')
  assert(program.plays.empty?, 'Opening the tutorial played a sound automatically')
  assert(form.instance_variable_get(:@tutorial_opening_header) == 'Welcome to the audio tutorial. Here you will learn the sounds used in this game. Use the arrow keys to browse. Press Space or Enter to play a sound.', 'Tutorial did not put its welcome before the first item')
  assert(list.header == 'Audio tutorial', 'The welcome remained in the list header after opening')
  assert(!form.instance_variable_get(:@quiet), 'The first wait will cut off the welcome with another focus announcement')
  list.trigger(:select)
  first = program.plays.last
  assert(first[0] == 'audio_ball_up' && first[1] == {volume: 0.4, sample: false, loop: false}, 'Enter did not play the selected asset once with the Game Room volume')
  list.define_singleton_method(:key_first_pressed?) { |_key| true }
  list.trigger(:key_space)
  assert(program.plays.length == 2 && first[2].closed, 'Space did not restart playback without overlapping the previous sound')
  list.define_singleton_method(:key_first_pressed?) { |_key| false }
  list.trigger(:key_space)
  assert(program.plays.length == 2, 'Holding Space repeatedly restarted playback')
  list.index = 1
  list.trigger(:move)
  assert(program.plays.last[2].closed && program.plays.length == 2, 'Arrow navigation did not stop playback or started another sound')
  list.trigger(:select)
  assert(program.plays.last[0] == 'audio_ball_left', 'The selected sound does not match its label')
  form.trigger(:key_escape)
  assert(form.instance_variable_get(:@resumed), 'Escape did not return from the tutorial')
end
assert(GameRoomAudioTutorial.instance_methods.include?(:wait), 'The common audio tutorial has no playable list')
GameRoomAudioTutorial.new(entries, program: program).wait
assert(program.plays.last[2].closed, 'Leaving the tutorial leaked its last sound')
Form.tutorial_driver = ->(_form) { raise 'An empty tutorial opened a form' }
GameRoomAudioTutorial.new([], program: program).wait

program = TutorialProgram.new
Form.tutorial_driver = lambda do |form|
  list = form.fields.first
  program.volume = 0
  list.trigger(:select)
  assert(program.plays.empty? && $spoken_messages.last == 'This sound is muted in Power Games settings.', 'Muted volume was ignored or left unexplained')
  program.volume, program.enabled = 0.6, false
  list.trigger(:select)
  assert(program.plays.empty?, 'Disabled sound was played')
  program.enabled, program.missing = true, true
  list.trigger(:select)
  assert($spoken_messages.last == 'This sound could not be played.', 'Missing asset failed without feedback')
  program.missing = false
  list.trigger(:select)
  assert(program.plays.last[1][:volume] == 0.6, 'Playback did not read the current volume')
  raise 'Simulated host interruption'
end
begin
  GameRoomAudioTutorial.new(entries, program: program).wait
  raise 'The simulated interruption disappeared'
rescue RuntimeError => error
  raise unless error.message == 'Simulated host interruption'
end
assert(program.plays.last[2].closed, 'A host interruption leaked the tutorial sound')

# Resolve at playback, so a tutorial prepared before Ctrl+P still follows the
# current local pack. Ordinary entries in other games remain static assets.
program = TutorialProgram.new
pack_id = 'default'
program.define_singleton_method(:audio_ball_preferences) { {'sound_pack' => pack_id} }
Form.tutorial_driver = lambda do |form|
  list = form.fields.first
  %w[audiodisc default invalid].each do |chosen|
    pack_id = chosen
    expected = GameRoomAudioBall::SoundPack::PACKS.fetch(chosen, GameRoomAudioBall::SoundPack::DEFAULT)
    entries.each_with_index do |entry, index|
      list.index = index
      list.trigger(:select)
      role = %w[up left down prepare stop][index]
      assert(program.plays.last.first == expected.fetch(role), 'Tutorial ignores the current local sound pack')
    end
  end
  form.trigger(:key_escape)
end
GameRoomAudioTutorial.new(entries, program: program).wait
static = GameRoomAudioTutorial::Entry.new(label: 'Other game', asset: 'draw')
assert(static.asset_for(program) == 'draw', 'Audio Ball pack changes another game tutorial')
assert(program.plays.last[2].closed, 'Pack previews leaked a playing sound')
puts 'PASS audio tutorial: reusable entries, labels, welcome, Enter/Space, navigation, empty list, mute, missing assets and exceptional cleanup'
