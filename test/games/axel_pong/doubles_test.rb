require_relative "../../support/ui"
require_relative "../../support/log"
class Program
  def self.server_app(**_options); end
end
require_relative "../../../__app"

def assert(value, message); raise message unless value; end

game = GameRoomGames::AxelPong.new
options = game.option_definitions
assert(options.map(&:key) == %w[arcade team_size difficulty target custom_target p2p_enabled p2p_participants_limit], 'Pong option order changed')
mode = options[1]
assert(mode.kind == :choice && mode.default == 0, 'Single is not the default arrow-key choice')
assert(mode.choices.map { |choice| [choice.value, choice.label] } == [[0, 'Single'], [2, 'Doubles']], 'wrong Single/Doubles choices')
assert(game.maximum_players == 4, 'a doubles table cannot seat four players')
[0, 2].each do |size|
  selected = game.normalize_options('team_size' => size)
  assert(game.validation_error(selected) == nil, 'table creation requires players before they can join')
  (1..5).each do |count|
    expected = size == 2 ? 4 : 2
    assert((game.validation_error(selected, player_count: count) == nil) == (count == expected), "wrong player limit for #{size}: #{count}")
  end
end
players = %w[A B C D]
doubles = game.normalize_options('team_size' => 2)
assert(game.team_assignment(doubles, players: players).seats == [0, 1, 0, 1], 'doubles does not use the shared team assignment')
manual = game.with_team_assignment(doubles, players: players, seats: [0, 0, 1, 1])
assert(game.team_assignment(game.options_from_json(JSON.generate(manual)), players: players).members_for(0) == %w[A B], 'manual teams did not survive session options')
assert(game.validation_error(manual.merge('team_seats' => [0, 0, 0, 1]), player_count: 4) != nil, 'unbalanced teams were accepted')
repository = Object.new
def repository.players_for(session); session['__players']; end
def repository.actor_of(event, _session); event['actor']; end
def repository.event_id(event); event['__id']; end
session = {'__players' => players, '__insertion_user' => 'Owner', 'player_one' => 'A', 'options' => JSON.generate(manual)}
events = 11.times.map { |i| {'__id' => i + 1, '__insertion_user' => 'Owner', 'action' => 'pong_point', 'value' => "#{i}:0"} }
replay = game.replay(session, events, repository)
assert(replay.state[:scores] == [11, 0] && replay.winner == 'team:0', 'doubles points did not produce a team winner')
assert(game.participant_scores(replay) == {'A' => 11, 'B' => 11, 'C' => 0, 'D' => 0}, 'teammates do not share their score')
players.each_with_index do |player, i|
  assert(game.bot_reward(replay, player) == (i < 2 ? 1.0 : -1.0), "wrong doubles result for #{player}")
end
assert(game.bot_reward(replay, 'Watcher') == 0.0, 'observer received a player result')
assert(game.bot_allied?(replay, 'a', 'B') && !game.bot_allied?(replay, 'A', 'C'), 'doubles alliances ignore chosen teams')
assert(game.result_text(replay).include?('A and B') && !game.result_text(replay).include?('team:0'), 'team result exposes an internal identifier')
assert(replay.history.last.text.include?('A and B'), 'result history omits the winning partners')
assert(game.replay(session, events + [events.last], repository).state[:scores] == [11, 0], 'duplicate point scored again')
forged = events.map { |event| event.merge('__insertion_user' => 'Mallory') }
assert(game.replay(session, forged, repository).state[:scores] == [0, 0], 'unauthenticated doubles points accepted')
[players.take(3), players + ['E'], %w[A A C D]].each do |invalid|
  assert(game.replay(session.merge('__players' => invalid), events, repository).accepted_events.empty?, 'invalid doubles roster scored')
end
[[0, 0, 0, 1], [0, 1], [0, 1, 2, 2], ['x', 0, 1, 1], nil].each do |seats|
  invalid = session.merge('options' => JSON.generate(manual.merge('team_seats' => seats)))
  assert(game.replay(invalid, events, repository).accepted_events.empty?, 'malformed doubles teams scored')
end
# Invalid shared collection shapes are refused before game replay. They must
# not be normalized to an unrelated automatic team assignment.
[false, true, {}, [0, {}, 1, 1], [0, true, 1, 1]].each do |seats|
  invalid_options = manual.merge('team_seats' => seats)
  original = JSON.generate(invalid_options)
  assert(game.validation_error(invalid_options, player_count: 4) != nil, 'malformed team shape passed setup validation')
  begin
    game.replay(session.merge('options' => original), events, repository)
    raise 'malformed team shape reached doubles replay'
  rescue ArgumentError => error
    assert(error.message == 'Invalid game option shape', 'unexpected malformed-team failure')
  end
  assert(JSON.generate(invalid_options) == original, 'rejecting malformed teams changed the input')
end
single_session = session.merge('__players' => players.take(2), 'options' => '{}')
assert(game.replay(single_session, events, repository).winner == 'A', 'legacy singles winner changed')
[nil, [0, 0, 1, 1], [0, 1, 0, 1], [1, 1, 0, 0]].each do |seats|
  history_session = seats ? session.merge('options' => JSON.generate(manual.merge('team_seats' => seats))) : single_session
  2.times do |side|
    point_event = events.first.merge('value' => "0:#{side}")
    point_history = game.replay(history_session, [point_event], repository).history
    point = point_history.find { |entry| entry.key == 'point:1' }
    expected_actor = seats ? "team:#{side}" : players[side]
    assert(point && point.actor == expected_actor, "wrong point actor for #{seats.inspect}, side #{side}: expected #{expected_actor.inspect}, got #{point&.actor.inspect}")
    timeout_event = point_event.merge('value' => "0:#{side}:timeout")
    timeout_history = game.replay(history_session, [timeout_event], repository).history
    timeout = timeout_history.find { |entry| entry.key == 'timeout:1' }
    expected_actor = seats ? "team:#{1 - side}" : players[1 - side]
    assert(timeout && timeout.actor == expected_actor, "wrong timeout actor for #{seats.inspect}, side #{side}: expected #{expected_actor.inspect}, got #{timeout&.actor.inspect}")
  end
end
running = game.replay(session, events.take(3), repository)
spec = game.surface_spec(running, 'D')
surface = GameSurfaces.build(spec)
$spoken_messages.clear
surface.handle_command('scores')
assert($spoken_messages == ["Team A: A and B. Points: 3. Team B: C and D. Points: 0.\nScore limit: 11 points."],
  'S does not read both teams, partners, scores and the winning target with punctuation')
surface.present({'server' => 3, 'receiver' => 1, 'p' => [4, 8, 12, 16], 'shields' => [0, 0, 0, 0]}, 'Ready.')
$spoken_messages.clear
surface.handle_command('server')
assert($spoken_messages == ['D will serve against B. Ready.'], 'T omits the actual receiving player')
surface.handle_command('position')
assert($spoken_messages.last == 'Paddle: 16.', 'fourth player reads another paddle position')
doubles_rules = game.rule_sections.find { |section| section.id == :doubles }
assert(doubles_rules, 'in-game rules omit doubles')
assert(doubles_rules.paragraphs.join(' ').include?('same 2.7-second serve delay as in Single'), 'in-game rules omit the shared first-serve break')
puts 'PASS Pong doubles options, shared assignments, player counts, durable team results, S/T/C readouts and rules'
