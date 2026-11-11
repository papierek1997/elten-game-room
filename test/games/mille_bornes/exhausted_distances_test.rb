require_relative '../../../games/mille_bornes'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

game = GameRoomGames::MilleBornes.new
def distance_position(game, remaining, miles: [950, 975], reverse: false)
  options = game.normalize_options('recycle_discard' => true, 'counterflow' => reverse)
  state = game.send(:initial_state, %w[Alice Bob], options)
  state[:phase], state[:current_player], state[:seed] = :playing, 'Alice', '0' * 32
  state[:round] = 1
  state[:hands] = {'Alice' => ['go:1'], 'Bob' => ['go:2']}
  state[:tracks].each_with_index { |track, index| track[:miles] = miles[index]; track[:moving] = true }
  game.send(:deck_for, options).each do |card|
    type, copy = card.split(':')
    state[:spent] << card if GameRoomGames::MilleBornes::DISTANCES.include?(type) && copy.to_i > remaining.fetch(type, 0)
  end
  state
end

state = distance_position(game, {})
assert(game.send(:round_over?, state), 'A recycled deck with no distances never ends')
assert(!game.send(:distance_finish_impossible?, distance_position(game, {'50' => 1})), 'The last usable 50-mile card was ignored')
assert(!game.send(:distance_finish_impossible?, distance_position(game, {'25' => 1})), 'The last usable 25-mile card was ignored')
assert(game.send(:distance_finish_impossible?, distance_position(game, {'100' => 4})), 'Unusable exact-finish distances keep the round alive')
state[:options]['recycle_discard'] = false
assert(!game.send(:round_over?, state), 'Traditional nonrecycling play ended before hands ran out')
state = distance_position(game, {'200' => 1}, miles: [800, 800])
state[:tracks].each { |track| track[:two_hundreds] = 2 }
assert(game.send(:distance_finish_impossible?, state), 'A forbidden third 200-mile card kept the round alive')
assert(!game.send(:distance_finish_impossible?, distance_position(game, {'100' => 12}, reverse: true)),
  'Potential reverse/reset travel was prematurely ruled out')

state = distance_position(game, {'50' => 1})
state[:private_cards], state[:private_viewer] = true, 'Alice'
state[:hands]['Bob'] = ['hidden:secret:0']
assert(!game.send(:distance_finish_impossible?, state), 'Private hands changed the public impasse decision')
state[:tracks][0][:moving] = false
state[:tracks][0][:hazards] = ['flat_tire']
assert(!game.send(:distance_finish_impossible?, state), 'A temporary hazard was treated as proof of an impasse')
state[:reaction] = {token: 'reaction'}
state[:spent] << '50:1'
assert(!game.send(:distance_finish_impossible?, state), 'An impasse cut off the dirty-trick response window')

# Real accepted draw -> the ordinary settlement; no completion bonus, no
# injected deck or direct state replacement in the event application path.
state = distance_position(game, {})
state[:phase], state[:draw_pile] = :awaiting_draw, ['go:3']
history = []
assert(game.send(:apply_standard_event, state, {'action' => 'draw', 'value' => '', 'id' => 1}, 'Alice', 1, history),
  'Normal draw could not settle the impasse')
assert(state[:phase] == :round_complete && state[:round_scores] == [950, 975] && state[:round_winner].nil?,
  'Impass settlement awarded a finish bonus or lost existing points')
assert(history.any? { |entry| entry.text.include?('remaining distance cards') }, 'Impass has no explanation')
assert(state[:draw_pile].empty? && state[:hands]['Alice'] == ['go:1', 'go:3'], 'Settlement manufactured or lost cards')

# Check safety against an independent exhaustive search which allows any
# order of a small number of forward/backward cards and start-line clipping.
def reachable_finish?(miles, cards)
  pending, seen = [[miles, cards.sort]], {}
  until pending.empty?
    position, remaining = pending.pop
    return true if position == 1000
    next if seen[[position, remaining]]
    seen[[position, remaining]] = true
    remaining.uniq.each do |distance|
      tail = remaining.dup
      tail.delete_at(tail.index(distance))
      [-distance, distance].each do |change|
        target = [position + change, 0].max
        pending << [target, tail] if target <= 1000
      end
    end
  end
  false
end
[0, 25, 775, 900, 925, 950, 975].each do |miles|
  [[25, 50, 75, 100], [25, 100, 100, 200], [75, 75, 100, 100]].each do |cards|
    next unless reachable_finish?(miles, cards)
    counts = cards.tally.transform_keys(&:to_s)
    assert(!game.send(:distance_finish_impossible?, distance_position(game, counts, miles: [miles, miles], reverse: true)),
      'Optimistic public reachability rejected a real backwards/forwards path')
  end
end
puts 'PASS recycled-mile impasses: public/private consistency, exact finish, 200 limit, reverse travel, reactions and standard scoring'
