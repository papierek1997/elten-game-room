require_relative '../../support/private_card_games'
require_relative '../../../games/cribbage_support/cribbage_table'

def drive_cribbage(h, runners, limit: 100)
  limit.times do
    replay = h.replay(h.users.first)
    return replay if yield(replay)
    actor = replay.current_player
    actions = actor && h.game.legal_actions(h.replay(actor), actor)
    if actor && actions && !actions.empty? && replay.state[:phase] != :round_complete
      PrivateCardGamesTest.submit(h, runners, actor, actions.first)
    else
      PrivateCardGamesTest.tick(h, runners)
    end
  end
  raise 'Cribbage scenario exceeded its action bound'
end

game = GameRoomGames::CribbageTable.new
h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob], clock: ClockEventContract::ManualTime.new)
begin
  drive_cribbage(h, runners) { |replay| replay.state[:phase] == :playing }
  actor = h.replay('Alice').current_player
  PrivateCardGamesTest.submit(h, runners, actor, game.legal_actions(h.replay(actor), actor).first)
  actor = h.replay('Alice').current_player
  mine = h.replay(actor)
  assert(game.legal_actions(mine, actor).any? { |action| action['kind'] == 'card' }, 'False Go fixture has no playable card')
  assert(game.action_for({'kind'=>'command', 'action'=>'crib_go'}, mine, actor).first != :ok,
    'Honest input offers an illegal Go')
  h.write(actor, [GameRoomPrivateCards.command('crib_go', '', operation: 'claim')])
  result = drive_cribbage(h, runners) { |replay| replay.state[:private_error] || replay.state[:phase] == :manual_count || replay.finished? }
  assert(result.state[:private_error] == :invalid_round, 'False Go escaped the private audit')
  h.users.each do |viewer|
    replay = h.replay(viewer)
    assert(replay.state[:scores].values.all?(&:zero?) && !replay.finished?, 'Invalid hand published points or a winner')
    assert(replay.history.none? { |entry| entry.kind == :result }, 'Invalid hand announced a result')
  end
ensure
  runners.each_value(&:close)
end

h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob], clock: ClockEventContract::ManualTime.new)
begin
  result = drive_cribbage(h, runners, limit: 200) do |replay|
    raise 'Valid private hand failed its audit' if replay.state[:private_error]
    replay.state[:round] >= 3 && replay.state[:phase] == :discard
  end
  PrivateCardGamesTest.assert_private(h)
  assert(result.state[:round] == 3, 'Private rounds did not retire and recreate pools')
  assert(h.users.map { |viewer| h.events(viewer) }.uniq.one?, 'Private clients disagree about the authenticated history')
  assert(h.users.map { |viewer| h.replay(viewer).state[:scores] }.uniq.one?, 'Audited private scores differ')
ensure
  runners.each_value(&:close)
end
h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob], clock: ClockEventContract::ManualTime.new)
begin
  saw_terminal_audit = false
  result = drive_cribbage(h, runners, limit: 1200) do |replay|
    raise 'Valid full private match failed its audit' if replay.state[:private_error]
    if replay.state[:scores].values.any? { |points| points >= 121 } && !replay.state[:private_crib_audited]
      saw_terminal_audit = true
      assert(!replay.finished? && !replay.winner, 'An unaudited private claim published the winner')
    end
    replay.finished?
  end
  assert(result.state[:private_crib_audited], 'Final hand was not audited')
  assert(h.users.map { |viewer| h.replay(viewer).winner }.uniq == [result.winner], 'Private clients disagree on the final winner')
  assert(result.history.count { |entry| entry.kind == :result } == 1, 'Final audit omitted or repeated the result')
ensure
  runners.each_value(&:close)
end

# Start one dedicated fixture near the target so a pegging award, rather
# than an already audited hand count, must exercise the disclosure gate.
class CribbageAuditBoundary < GameRoomGames::CribbageTable
  protected
  def initial_state(players, options)
    super.tap { |state| state[:scores].transform_values! { 120 } }
  end
end
h, runners = PrivateCardGamesTest.create(CribbageAuditBoundary.new, users: %w[Alice Bob], clock: ClockEventContract::ManualTime.new)
begin
  gate = drive_cribbage(h, runners) do |replay|
    replay.state[:scores].values.any? { |points| points >= 121 }
  end
  assert(!gate.finished? && !gate.winner && !gate.state[:private_crib_audited],
    'A private pegging award bypassed its terminal audit')
  result = drive_cribbage(h, runners) { |replay| replay.finished? || replay.state[:private_error] }
  assert(result.finished? && result.state[:private_crib_audited] && !result.state[:private_error],
    'A legal private pegging finish did not pass disclosure and the normal reducer')
ensure
  runners.each_value(&:close)
end
puts 'PASS private Cribbage: false Go rejected, retired-pool cold replay, hidden hands and a complete match whose winner waits for the terminal audit'
