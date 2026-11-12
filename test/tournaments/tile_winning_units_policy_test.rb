require_relative '../support/domino'
require_relative '../support/assertions'
require_relative '../../games/mexican_train'
require_relative '../../lib/tournaments/game_result'
require_relative '../../lib/tournaments/standings'
include GameRoomTest::Assertions

TileResultMatch = Struct.new(:game, :session, :repository, :events, :replay, :options, keyword_init: true) do
  def export(policy)
    GameRoomTournaments::GameResult.from_replay(game: game, replay: replay,
      players: replay.players.map { |name| {'username'=>name, 'account'=>name.downcase} },
      options: options, events: events, event_count: events.length, result_policy: policy)
  end
end

def finish_tile_match(game, players:, seed:, options: {})
  options = game.normalize_options(options)
  session = {'options'=>JSON.generate(options)}
  repository = NewGames116Repository.new(players)
  context = context_for(GameRoomRandom::SeededSource.new(seed))
  events = []
  replay = game.replay(session, events, repository)
  600.times do
    break if replay.finished?
    selection = game.automatic_action(replay, players.first, context: context)
    actor = selection ? players.first : replay.current_player
    selection ||= game.legal_actions(replay, actor, context: context).
      max_by { |action| game.bot_action_score(replay, actor, action, context: context) }
    assert(actor && selection, 'Ordinary tile match stalled')
    replay = append_action(game, session, repository, events, replay, actor, selection, context)
    assert_equal(events, replay.accepted_events, 'Ordinary tile match rejected a committed action')
  end
  assert(replay.finished?, 'Ordinary tile match did not finish')
  TileResultMatch.new(game: game, session: session, repository: repository, events: events, replay: replay, options: options)
end

type = GameRoomTournaments::GameResult
players = %w[Alice Bob Carol Dave Eve Frank Grace Heidi]
match = finish_tile_match(GameRoomGames::MexicanTrain.new, players: players, seed: 87,
  options: {'score_limit'=>1})
assert_equal(98, match.events.length, 'Accepted blocked-match fixture changed')
assert_equal(%w[Alice Heidi], match.replay.state[:winners])
assert_equal({'Alice'=>8,'Bob'=>22,'Carol'=>60,'Dave'=>26,'Eve'=>10,'Frank'=>14,'Grace'=>28,'Heidi'=>8},
  match.game.participant_scores(match.replay))
before = Marshal.dump([match.replay, match.session, match.events])
assert_equal('game-owned-result-v8', type::CURRENT_RESULT_POLICY)
current = match.export(type::CURRENT_RESULT_POLICY)
assert_equal(%w[alice heidi], current['winners'], 'Current result dropped a public tied winner')
assert_equal(false, current['draw'])
assert_equal(match.game.participant_scores(match.replay).transform_keys(&:downcase), current['scores'])
assert_equal('lower', current['score_order'])
table = GameRoomTournaments::Standings.calculate(units: players.map(&:downcase),
  results: [current.slice('participants', 'winners', 'scores', 'score_order', 'places').merge('id'=>'blocked-tile-match')],
  points: GameRoomTournaments::Standings::MATCH_POINTS)
rows = table.to_h { |row| [row['unit'], row] }
assert_equal(rows.fetch('alice')['points'], rows.fetch('heidi')['points'], 'Public co-winners received different match points')
assert(rows.fetch('alice')['points'] > rows.fetch('eve')['points'], 'Co-winners did not lead the match')

# Historical receipts keep their original exports, even when that older
# export omitted the co-winner. The new policy is chosen only for new binds.
[nil, *type::EXPORT_POLICIES.reject { |policy| policy == type::WINNING_UNITS_RESULT_POLICY }].each do |policy|
  legacy = match.export(policy)
  assert_equal(['alice'], legacy['winners'], "Historical #{policy.inspect} winners changed")
  assert_equal(false, legacy['draw'])
  if policy.nil? || policy == type::RESULT_EXPORT_POLICY || policy == type::DRAW_RESULT_POLICY || policy == type::SCORE_EXPORT_POLICY
    assert_equal(nil, legacy['scores'])
  elsif [type::SCORE_ORDER_POLICY, type::RANKING_RESULT_POLICY].include?(policy)
    assert_equal(nil, legacy['scores'])
    assert_equal('higher', legacy['score_order'])
  else
    assert_equal(current['scores'], legacy['scores'])
    assert_equal('lower', legacy['score_order'])
  end
end
assert_equal(before, Marshal.dump([match.replay, match.session, match.events]), 'Result export mutated the completed match')

# Reuse the game-family hook, including teams: there is no tournament game-ID
# switch and no generic inference from arbitrary state[:winners] fields.
domino = GameRoomGames::Domino.new
%w[individual teams].each do |mode|
  roster = mode == 'teams' ? %w[Alpha Beta Gamma Delta] : %w[Alpha Beta]
  options = {'score_limit'=>1}
  if mode == 'teams'
    options = domino.with_team_assignment(domino.normalize_options(options.merge('teams'=>true, 'team_count'=>'2')),
      players: roster, seats: [0, 1, 0, 1])
  end
  control = finish_tile_match(domino, players: roster, seed: 17, options: options)
  old = domino.tournament_placement_result(control.replay, options: control.options)
  assert_equal(old, domino.tournament_winning_units_result(control.replay, options: control.options),
    "Domino #{mode} changed its existing winning units")
end
puts 'PASS complete ordinary Mexican Train shared win, unchanged v1-v7 exports, match points and shared Domino team/individual hook'
