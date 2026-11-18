require_relative '../../support/cheat'
include GameRoomTest::CheatFixture

cheat_start
actor = @replay.current_player
hand = @replay.state[:hands].fetch(actor)
selection = cheat_play(hand.first(2))
dialog = @game.surface_action_shortcut(selection, @replay, actor)
assert_equal([], dialog.fields)
assert_equal('Play', dialog.submit_label)
assert(dialog.prompt.include?('2 aces'))
assert_equal(selection['cards'], dialog.payload['cards'])
assert_equal(@replay.state[:sequence].to_s(36), dialog.payload['boundary'])
assert_equal('A', dialog.payload['choice'])
assert_equal(hand.sort, @game.playable_card_navigation(@replay, actor)[:card_actions].keys.sort)
assert_equal([], @game.playable_card_navigation(@replay, actor)[:automatic_card_ids])
assert_equal(nil, @game.playable_card_navigation(@replay, @players.last))
assert_equal([], @game.surface_spec(@replay, 'Observer').cards)
assert_equal(nil, @game.participant_scores(@replay))
cheat_move(selection)
public_text = @game.send(:public_text, @replay.state)
assert(!hand.first(2).any? { |card| public_text.include?(@game.send(:playing_card_label, card)) })
history = @replay.history.map(&:text).join(' ')
assert(!hand.first(2).any? { |card| history.include?(@game.send(:playing_card_label, card)) })
keys = @game.game_shortcuts(@replay, @replay.current_player).map { |shortcut| [shortcut.key, shortcut.modifiers] }
assert(keys.include?(['k', []]) && keys.include?(['space', []]))
assert(!keys.include?(['x', []]))
assert_equal(nil, @game.playable_card_navigation(@replay, @replay.current_player))
puts 'PASS Cheat presentation: final confirmation, physical card navigation, phase shortcuts and hidden cards'
