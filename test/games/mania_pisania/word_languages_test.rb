# encoding: UTF-8
require_relative '../../support/game_option_form'
require_relative '../../../lib/mania_pisania/word_bank'
require_relative '../../../lib/mania_pisania/practice'

game = GameRoomGames::ManiaPisania.new
%w[en pl cs es ru].each do |language|
  GameRoomLocalization.boot(host_language: language)
  created = game.table_creation_options('variant'=>'words')
  assert(created['word_language'] == language, 'New table must use its creator\'s language')
  assert(game.table_creation_options('word_language'=>'cs')['word_language'] == 'cs', 'Explicit dictionary was lost')
  assert(game.options_from_json('{"variant":"memory"}')['word_language'] == 'pl', 'Old games must retain the Polish dictionary')
  bank = GameRoomTyping::WordBank.for_options(created)
  sample = 100.times.map { |index| bank.call(123, index) }
  assert(sample.uniq.length > 80, "Poor sample diversity for #{language}")
  assert(sample.all? { |word| word.length.between?(3,12) && GameRoomTyping::KeyboardText.unsupported(word).empty? }, 'Unplayable word')
  GameRoomLocalization.boot(host_language: language == 'en' ? 'ru' : 'en')
  guest = GameRoomTyping::WordBank.for_options(game.options_from_json(JSON.generate(created)))
  assert(sample == 100.times.map { |index| guest.call(123, index) }, 'Guest interface changed the shared word sequence')
  %w[words memory survival].each do |variant|
    practice = GameRoomTyping::Practice.new(options: created.merge('variant'=>variant, 'input'=>'keyboard'),
      word_bank: bank, seed:123, multiplayer:false, recording_seconds:120)
    practice.start
    checkpoint = practice.snapshot
    assert(GameRoomTyping::Checkpoint.valid?(checkpoint, variant:variant, seed:123), 'Checkpoint is invalid')
    GameRoomTyping::Checkpoint.validate_word_source!(checkpoint, word_bank:guest)
    private_data = {'format'=>1, 'checkpoint'=>checkpoint, 'source'=>nil}
    replay = Struct.new(:state,:players).new({phase: :active, seed:123, options:created.merge('variant'=>variant)},['Alice'])
    game.validate_saved_private_data(replay, private_data)
    restored = GameRoomTyping::Practice.new(options: created.merge('variant'=>variant, 'input'=>'keyboard'),
      word_bank:guest, seed:123, multiplayer:false, recording_seconds:120)
    restored.restore(checkpoint)
    restored.resume
    assert(restored.engine.snapshot['word'] == checkpoint['engine']['word'], 'Restoration changed the current word')
  end
end
puts 'PASS five word languages, shared seeds across interfaces, default Polish language and checkpoints in all word variants.'
