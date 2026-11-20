require_relative '../../support/assertions'
require_relative '../../../lib/game_simulation'
require_relative '../../../lib/game_sounds'
require_relative '../../../games/cribbage_support/cribbage_table'
include GameRoomTest::Assertions

game = GameRoomGames::CribbageTable.new
players = %w[Alice Bob]
assert_equal(121, game.default_options.fetch('score_limit'))
assert(game.validation_error({'score_limit'=>0}), 'Zero-point target must be rejected')
assert(game.validation_error({'score_limit'=>-1}), 'Negative target must be rejected')

short = GameRoomSimulation::Environment.new_game(game: game, players: players, seed: 2,
  options: {'score_limit'=>2})
assert_equal(2, game.score_target(short.replay))
4.times { assert_equal(:ok, short.step(short.legal_actions.first)) }
assert(short.finished?, 'A jack starter must end a game played to two points')

heard = []
8.times do |seed|
  env = GameRoomSimulation::Environment.new_game(game: game, players: players, seed: seed)
  while !env.finished? && env.replay.state[:round] == 1 && env.replay.state[:phase] != :round_complete
    before = env.replay
    before_phase = before.state[:phase]
    actions = env.legal_actions
    total = before.state[:sequence].sum { |value| [value, 10].min }
    exact = actions.find do |action|
      card = action['card']
      total.positive? && card && total + [GameRoomGames::CribbageCards.decode(card).first, 10].min == 31
    end
    assert_equal(:ok, env.step(exact || actions.first))
    after = env.replay
    event = env.events.last
    cues = Array(GameRoomSounds.event_cue(game: game, event: event, before_replay: before,
      after_replay: after, repository: env.repository, viewer: players.first))
    heard.concat(cues)
    assert(!cues.include?('ding') || event['action'] == 'play', 'Score effect leaked into manual counting')
    if cues.include?('draw2')
      assert_equal('play', event['action'])
      rank = GameRoomGames::CribbageCards.decode(event.fetch('value')).first
      assert_equal(31, total + [rank, 10].min)
      assert(!cues.include?('ding'), 'The 31 effect must replace the normal score effect')
    end
    assert_equal(after.state[:phase] == :manual_count && before_phase != :manual_count,
      cues.include?('round_finished'), 'End-of-play effect must sound just before counting')
  end
end
assert_equal([], %w[ding draw2 round_finished] - heard, 'Missing sound effects')
puts 'PASS Cribbage score limit and round sound effects'
