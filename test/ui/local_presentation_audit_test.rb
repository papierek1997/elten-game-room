require_relative '../support/duck_challenge_native'
require_relative '../support/cheat'
require_relative '../../games/tic_tac_toe'
require_relative '../../lib/local_game_presentation'
require_relative '../../lib/presentation_replay'
include GameRoomTest::Assertions

class ReceiverAuditGame < GameRoomGames::TicTacToe
  def replay(session, events, repository)
    super.tap { |result| result.state = {observations: events.select { |row| row['action'] == 'observation' }.map { |row| row['value'] }} }
  end
end
runtime = Object.new
runtime.define_singleton_method(:read_json) { |_path, default: nil| default }
runtime.define_singleton_method(:write_json) { |_path, _value| true }
names = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Alice')
names.save('Anna Żółć')
game = ReceiverAuditGame.new
repository = GameRoomTest::CheatFixture::Repository.new(%w[Alice Bob])
session = {'options' => '{}'}
raw = [
  {'id' => 1, 'actor' => 'Alice', 'action' => 'place', 'value' => '1,1'},
  {'id' => 2, 'actor' => 'Alice', 'action' => 'observation', 'value' => 'authenticated refused observation'},
  {'id' => 3, 'actor' => 'Bob', 'action' => 'place', 'value' => '2,1'},
  {'id' => 4, 'actor' => 'Alice', 'action' => 'place', 'value' => '3,1'}]
original_raw = Marshal.dump(raw)
canonical = game.replay(session, raw, repository)
assert_raises(ArgumentError) do
  GameRoomPresentationReplay.new(game, repository, raw_input: ->(_session) { raw }).transitions(session, canonical,
    [canonical.accepted_events.first, canonical.accepted_events.last])
end
transitions = GameRoomPresentationReplay.new(game, repository, raw_input: ->(_session) { raw }).transitions(session, canonical, canonical.accepted_events)
renderer = GameRoomLocalGamePresentation.new(game, names)
transitions.each do |id, pair|
  pair.each do |boundary|
    local = renderer.replay(session, raw, repository, boundary: boundary)
    assert_equal(boundary.state, local.state)
    assert_equal(boundary.accepted_events, local.accepted_events)
    assert(!local.accepted_events.any? { |row| row['id'] == 2 }, 'A refused observation became an accepted move')
  end
end
assert_equal([], transitions.fetch(1).last.state[:observations])
assert_equal(['authenticated refused observation'], transitions.fetch(3).first.state[:observations])
assert_equal(original_raw, Marshal.dump(raw), 'The raw audit tape changed')
newer = raw.map { |row| row.merge('created_at' => 1234) } +
  [{'id' => 5, 'actor' => 'Alice', 'action' => 'observation', 'value' => 'future observation'}]
transitions.each_value do |pair|
  pair.each do |boundary|
    local = renderer.replay(session, newer, repository, boundary: boundary)
    assert_equal(boundary.state, local.state, 'A newer audit tape replaced the captured private boundary')
    assert_equal(boundary.accepted_events, local.accepted_events)
  end
end
puts 'PASS presentation raw audit boundary: refused observations remain chronological evidence, exact accepted sequence, no future knowledge, no accepted-only reconstruction'
