require_relative '../../support/cheat'
include GameRoomTest::CheatFixture

%w[ascending descending neighbour suit fixed_bluff].each do |variant|
  limits = variant == 'fixed_bluff' ? [3, 6] : [2, 8]
  limits.each do |count|
    cheat_start(variant, count)
    assert_equal(:playing, @replay.state[:phase])
    sizes = @replay.state[:hands].values.map(&:length)
    assert(sizes.max - sizes.min <= 1, 'Deal is not balanced')
    cheat_conservation(@replay.state)
  end
  cheat_start(variant, limits.first)
  assert(@game.options_error({'variant' => variant}, player_count: limits.first - 1))
  assert(@game.options_error({'variant' => variant}, player_count: limits.last + 1))
  until @replay.finished?
    if @replay.state[:phase] == :reaction
      cheat_move(cheat_command('accept'))
    else
      hand = @replay.state[:hands].fetch(@replay.current_player)
      cheat_move(cheat_play(hand.first(variant == 'suit' ? 1 : 4)))
    end
  end
  assert(@players.include?(@replay.winner))
  assert_equal(@replay, @game.replay(@session, @events, @repository))
  assert_equal(nil, @game.participant_scores(@replay))
end

cheat_start
actor = @replay.current_player
hand = @replay.state[:hands].fetch(actor)
base = Marshal.dump(@replay)
[[], hand.first(5), [hand.first, hand.first], [(@game.send(:standard_deck) - hand).first]].each do |cards|
  assert_equal(:invalid_packet, @game.action_for(cheat_play(cards), @replay, actor).first)
  assert_equal(base, Marshal.dump(@replay), 'Refusal mutated the replay')
end
assert_equal(:not_your_turn, @game.action_for(cheat_play(hand.first(1)), @replay, @players.last).first)
packet = hand.first(4)
cheat_move(cheat_play(packet))
author = actor
assert_equal((@players.index(author) + 1) % 3, @players.index(@replay.current_player))
old_response = cheat_command('accept')
cheat_move(old_response)
assert_equal(:stale_packet, @game.action_for(old_response, @replay, @replay.current_player).first)
recipient = @replay.current_player
truth = packet.all? { |card| card.start_with?('A') }
cheat_move(cheat_command('challenge'))
assert_equal([], @replay.state[:pile])
assert_equal(packet.sort, @replay.state[:revealed].keys.sort)
assert_equal(@players[(@players.index(author) + 1) % 3], @replay.current_player)
assert_equal('2', @game.send(:allowed_claims, @replay.state).first)
expected = truth ? recipient : author
assert(packet.all? { |card| @replay.state[:hands].fetch(expected).include?(card) })
before = @replay.accepted_events.dup
assert_equal(before, @game.replay(@session, @events + [@events.last], @repository).accepted_events)

%w[ascending descending neighbour].each do |variant|
  cheat_start(variant)
  state = @replay.state
  state[:last_claim] = 'K'
  expected = {'ascending' => ['A'], 'descending' => ['Q'], 'neighbour' => %w[Q K A]}.fetch(variant)
  assert_equal(expected, @game.send(:allowed_claims, state))
  state[:last_claim] = 'A'
  expected = {'ascending' => ['2'], 'descending' => ['K'], 'neighbour' => %w[K A 2]}.fetch(variant)
  assert_equal(expected, @game.send(:allowed_claims, state))
end

cheat_start('fixed_bluff')
assert_equal(:invalid, @game.action_for(cheat_command('pass'), @replay, @replay.current_player).first)
opener = @replay.current_player
cheat_move(cheat_play(@replay.state[:hands].fetch(opener).first(2), '7'))
2.times { cheat_move(cheat_command('accept')) }
2.times { cheat_move(cheat_command('pass')) }
assert_equal(opener, @replay.current_player)
cheat_move(cheat_play(@replay.state[:hands].fetch(opener).first(1), '7'))
assert_equal(@players[(@players.index(opener) + 1) % 3], @replay.current_player, 'Passed player cannot react')
2.times { cheat_move(cheat_command('accept')) }
cheat_move(cheat_command('pass'))
assert_equal(opener, @replay.current_player)
assert_equal(3, @replay.state[:removed].length)
assert_equal({}, @replay.state[:revealed])
assert_equal([], @replay.state[:passed])
assert_equal(13, @game.send(:allowed_claims, @replay.state).length)

cheat_start('suit')
first = @replay.current_player
card = @replay.state[:hands].fetch(first).first
cheat_move(cheat_play([card]))
assert_equal(:playing, @replay.state[:phase])
assert_equal([card], @replay.state[:revealed].keys)
assert_equal([card[1]], @game.send(:allowed_claims, @replay.state))
assert_equal(:invalid, @game.action_for(cheat_command('challenge'), @replay, @replay.current_player).first)
puts 'PASS Cheat: all profiles, counts, complete accepted matches, conservation, refusals, response order, stale/duplicate moves, cycles, Bluff passes and suit opening'
