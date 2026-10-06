require_relative '../games/catalog'
require_relative 'support/private_simulation'
require_relative 'support/model_contract'
include GameRoomTest::Assertions

corpus = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v1/histories.json'), encoding: 'UTF-8'))
assert_equal(1, corpus.fetch('schema'))
cases = corpus.fetch('cases') + [JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v1/mille_bornes.json'), encoding: 'UTF-8'))]
expected_ids = GameRoomGames::CATALOG.ids.reject { |id| %w[axel_pong audio_ball].include?(id) }.sort
assert_equal(expected_ids, cases.map { |item| item.fetch('game') }.sort, 'corpus must explicitly cover every turn-based game')
assert((ARGV - expected_ids).empty?, 'unknown game requested for contract verification')
cases = cases.select { |item| ARGV.include?(item.fetch('game')) } unless ARGV.empty?
cases.each do |item|
  game = GameRoomGames::CATALOG.build(item.fetch('game'))
  random = Random.new(item.fetch('seed'))
  SecureRandom.define_singleton_method(:hex) { |n = 16| Array.new(n) { random.rand(256).to_s(16).rjust(2, '0') }.join }
  env = GameRoomTest::PrivateSimulation.new_game(game: game, players: item.fetch('players'), options: item.fetch('options'), seed: item.fetch('seed'))
  item.fetch('steps').each_with_index do |step, index|
    expected = step.reject { |key, _| key == 'action' }
    assert_equal(expected, GameRoomTest::ModelContract.checkpoint(env), "#{game.id}, step #{index}: contract changed")
    assert_equal(:ok, env.step(step.fetch('action'), actor: step.fetch('actor')), "#{game.id}: action rejected")
  end
  assert_equal(item.fetch('final'), GameRoomTest::ModelContract.checkpoint(env), "#{game.id}: final checkpoint changed")
  assert_equal(item.fetch('events'), env.events, "#{game.id}: serialized history changed")
  puts "#{game.id}: #{item.fetch('steps').length} transitions, full/incremental replay, input ownership, action order and RNG OK"
end
