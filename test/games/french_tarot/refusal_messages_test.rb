require_relative '../../support/french_tarot'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

game = GameRoomGames::FrenchTarotTable.new
encode = ->(suit, rank) { GameRoomGames::FrenchTarotCards.encode([suit, rank]) }
view = FrenchTarotFixture.match.replay.dup
view.current_player = 'Alice'
view.state = view.state.merge(phase: :discard, current_player: 'Alice', taker: 'Alice', kitty: [],
  hands: {'Alice'=>[encode.call(:clubs, 14), encode.call(:trump, 1), encode.call(:trump, 21),
    encode.call(:excuse, 0), encode.call(:trump, 5), encode.call(:hearts, 3)]})
select = ->(value) { {'kind'=>'card', 'action'=>'select', 'zone'=>'hand', 'card'=>value, 'card_id'=>value} }
snapshot = Marshal.dump(view)
view.state[:hands]['Alice'].take(4).each do |card|
  status, plan = game.action_for(select.call(card), view, 'Alice')
  assert_equal(:invalid, status)
  assert_equal(nil, plan)
  assert_equal('Kings and the three oudlers cannot be discarded.', game.move_error_for(status,
    selection: select.call(card), replay: view, actor: 'Alice'))
end
card = encode.call(:trump, 5)
status, = game.action_for(select.call(card), view, 'Alice')
assert_equal('Discard an ordinary suited card while you still have one that can be discarded.',
  game.move_error_for(status, selection: select.call(card), replay: view, actor: 'Alice'))
assert_equal(snapshot, Marshal.dump(view), 'A refusal or its explanation changed the hand')
without_suited = view.dup
without_suited.state = view.state.merge(hands: {'Alice'=>view.state[:hands]['Alice'].reject { |value| value == encode.call(:hearts, 3) }})
wrong_action = select.call(card).merge('action'=>'wrong')
assert_equal(game.move_error(:invalid), game.move_error_for(:invalid,
  selection: wrong_action, replay: without_suited, actor: 'Alice'), 'A malformed action blamed a nonexistent suited-card restriction')

view.state = view.state.merge(phase: :playing, current_player: 'Alice', trick: [['Bob', encode.call(:hearts, 2)]])
bad = select.call(encode.call(:clubs, 14))
assert_equal(:must_follow_suit, game.action_for(bad, view, 'Alice').first)
assert_equal('You must follow hearts.', game.move_error_for(:must_follow_suit, selection: bad, replay: view, actor: 'Alice'))
view.state[:hands]['Alice'].delete(encode.call(:hearts, 3))
view.state[:trick] = [['Bob', encode.call(:trump, 4)]]
assert_equal('You must play a trump higher than 4.', game.move_error_for(:must_follow_suit, selection: bad, replay: view, actor: 'Alice'))
view.state[:trick] = [['Bob', encode.call(:trump, 21)]]
assert_equal('You must play a trump.', game.move_error_for(:must_follow_suit, selection: bad, replay: view, actor: 'Alice'))
assert_equal(game.move_error(:not_your_turn), game.move_error_for(:not_your_turn, selection: bad, replay: view, actor: 'Bob'))
puts 'PASS French Tarot exact discard/follow-suit/trump/overtrump explanations without changing rules or hands'
