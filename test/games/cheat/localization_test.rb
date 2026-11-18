require_relative '../../support/duck_challenge_native'
require_relative '../../support/localization'
require_relative '../../support/cheat'
include GameRoomTest::CheatFixture
cheat_start
game = @game
playing = @replay
selection = cheat_play(playing.state[:hands].fetch(playing.current_player).take(1))
cheat_move(selection)
buttons = {'en' => ['Play', 'Challenge'], 'pl' => ['Zagraj', 'Sprawdzam'], 'cs' => ['Zahrát', 'Zkontrolovat'],
  'es' => ['Jugar', 'Comprobar'], 'ru' => ['Сыграть', 'Проверить']}
expected = {'en' => 'Cheat', 'pl' => 'Kłamczuch', 'cs' => 'Karetní podvodník',
  'es' => 'Mentiroso', 'ru' => 'Карточный блеф'}
expected.each do |language, title|
  GameRoomTestLocalization.use_language(language)
  assert_equal(title, game.name)
  assert_equal(5, game.variant_choices.length)
  assert_equal(buttons.fetch(language).first, game.surface_action_shortcut(selection, playing, playing.current_player).submit_label)
  assert_equal(buttons.fetch(language).last, game.send(:decision_commands, @replay, @replay.current_player).first.label)
  assert(game.variant_choices.all? { |choice| choice.label.encoding == Encoding::UTF_8 && choice.label.valid_encoding? }, 'Invalid variant encoding')
  assert_equal(3, game.rule_book(options: game.default_options).documents.length)
  if language == 'pl'
    assert_equal(['1 asa', '2 asy', '5 asów'], [1, 2, 5].map { |count| game.send(:declaration_text, 'A', count, 'ascending') })
    assert_equal(['1 kartę', '2 karty', '5 kart'], [1, 2, 5].map { |count| game.send(:card_count_text, count, received: true) })
  end
end
GameRoomTestLocalization.use_language('en')
assert_equal('Cheat', game.name)
puts 'PASS Cheat language changes on one instance: five UI/rulebook editions, Unicode and Polish declaration/received-card plural forms'
