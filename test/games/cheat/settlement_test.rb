require_relative '../../support/cheat'
include GameRoomTest::CheatFixture

def position(variant, author_cards, others: nil, empty_pile: false)
  cheat_start(variant, variant == 'fixed_bluff' ? 3 : 2)
  @players = @replay.players
  state = @replay.state
  state[:hands] = @players.to_h { |player| [player, []] }
  state[:hands][@players.first] = author_cards.dup
  rest = @game.send(:standard_deck) - author_cards
  @players.drop(1).each { |player| state[:hands][player] = [rest.shift] }
  if empty_pile
    state[:hands][@players.last].concat(rest)
    state[:pile] = []
  else
    state[:pile] = rest
  end
  state[:last_claim] = variant == 'suit' ? 'H' : variant == 'fixed_bluff' ? 'A' : nil
  state[:current_player] = @players.first
  @replay.current_player = @players.first
  @replay.history = []
  cheat_conservation(state)
end

def transition(selection)
  state = @replay.state
  actor = @replay.current_player
  status, plan = @game.action_for(selection, @replay, actor)
  assert_equal(:ok, status)
  event = {'id' => state[:sequence] + 1, 'actor' => actor, 'action' => plan.events.first.action, 'value' => plan.events.first.value}
  decoded = @game.send(:event_selection, event)
  assert_equal(:ok, @game.send(:validate_move, state, decoded, actor))
  @game.send(:apply_move, state, decoded, actor, event['id'], @replay.history)
  @replay.current_player, @replay.winner = state[:current_player], state[:winner]
  cheat_conservation(state)
  event
end

%w[ascending descending neighbour fixed_bluff].each do |variant|
  [['AC', true], ['KD', false]].each do |card, truth|
    position(variant, [card])
    author = @replay.current_player
    transition(cheat_play([card], 'A'))
    assert_equal(nil, @replay.winner, 'Last card won before reactions')
    transition(cheat_command('challenge'))
    assert_equal(truth ? author : nil, @replay.winner)
    assert_equal(truth ? [] : [card], @replay.state[:revealed].keys - (truth ? [card] : [])) unless truth
    assert_equal([card], @replay.state[:revealed].keys)
    assert_equal([], @replay.state[:pile])
    assert(@replay.state[:hands].fetch(author).length > 1, 'Caught final bluff failed to return the pile') unless truth
    position(variant, [card])
    author = @replay.current_player
    transition(cheat_play([card], 'A'))
    transition(cheat_command('accept')) while @replay.state[:phase] == :reaction
    assert_equal(author, @replay.winner, 'Unchecked last packet did not win')
  end
end

[[['AC', 'KS'], true], [['KD', 'KS'], false]].each do |cards, truth|
  position('fixed_bluff', cards)
  author = @players.first
  checker = @players[1]
  @replay.state[:passed] = [checker]
  transition(cheat_play(cards.first(1), 'A'))
  assert_equal(checker, @replay.current_player)
  transition(cheat_command('challenge'))
  assert_equal(truth ? author : checker, @replay.current_player)
  assert_equal([], @replay.state[:passed])
  assert_equal(nil, @replay.state[:last_packet])
  assert_equal(13, @game.send(:allowed_claims, @replay.state).length)
end

[['AH', true], ['AS', false]].each do |card, truth|
  position('suit', [card, 'KD'])
  author, checker = @players
  transition(cheat_play([card], 'H'))
  assert_equal(nil, @replay.winner)
  transition(cheat_command('challenge'))
  assert_equal(truth ? checker : author, @replay.current_player)
  assert_equal(nil, @replay.state[:last_claim])
  assert_equal([card], @replay.state[:revealed].keys)
end

position('suit', ['AH'], empty_pile: true)
author = @replay.current_player
transition(cheat_play(['AH'], ''))
assert_equal(author, @replay.winner)
assert_equal(:finished, @replay.state[:phase])
puts 'PASS Cheat production transitions: true/false final packets, no early winner, unchecked bluffs, passed challengers, Bluff openers, suit-only checks, hidden older pile and immediate face-up finish'
