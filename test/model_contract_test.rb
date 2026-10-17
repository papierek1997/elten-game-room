require_relative '../games/catalog'
require_relative 'support/private_simulation'
require_relative 'support/model_contract'
include GameRoomTest::Assertions

corpus = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v1/histories.json'), encoding: 'UTF-8'))
assert_equal(1, corpus.fetch('schema'))
# Build 242 added four roster/team fields to Tysiac. The reviewed v2 capture
# preserves every prior action, event, actor and RNG value; only full replay
# hashes differ. Keep the original v1 reference for the other models.
tysiac = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v2/tysiac.json'), encoding: 'UTF-8'))
previous_tysiac = corpus.fetch('cases').find { |item| item.fetch('game') == 'tysiac' }
without_replay_hashes = lambda do |item|
  item.merge('steps' => item.fetch('steps').map { |step| step.reject { |key, _| key == 'replay' } },
    'final' => item.fetch('final').reject { |key, _| key == 'replay' })
end
assert_equal(without_replay_hashes.call(previous_tysiac), without_replay_hashes.call(tysiac), 'Tysiac roster fields must not replace the reference actions or RNG')
# Build 251 removed question counts from the Quiz category announcement.
# Comparing the reference source and current full replay showed only this
# history text and its derived key changing; actions, events and RNG agree.
quiz = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v2/quiz.json'), encoding: 'UTF-8'))
previous_quiz = corpus.fetch('cases').find { |item| item.fetch('game') == 'quiz' }
assert_equal(without_replay_hashes.call(previous_quiz), without_replay_hashes.call(quiz), 'Quiz wording must not replace the reference actions or RNG')
cases = corpus.fetch('cases').reject { |item| %w[tysiac quiz].include?(item.fetch('game')) } + [tysiac, quiz,
  JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v1/mille_bornes.json'), encoding: 'UTF-8')),
  JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v1/bridge.json'), encoding: 'UTF-8'))]
duck = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v1/duck_racing.json'), encoding: 'UTF-8'))
expected_ids = GameRoomGames::CATALOG.ids.reject { |id| %w[axel_pong audio_ball].include?(id) }.sort
assert_equal(expected_ids, (cases.map { |item| item.fetch('game') } + [duck.fetch('game')]).sort, 'corpus must explicitly cover every turn-based game')
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

if ARGV.empty? || ARGV.include?('duck_racing')
  require_relative 'support/duck_model_contract'
  assert_equal(duck, GameRoomTest::DuckModelContract.capture(legacy: true), 'Historical Duck public protocol contract changed')
  current_duck = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v2/duck_racing.json'), encoding: 'UTF-8'))
  assert_equal(current_duck, GameRoomTest::DuckModelContract.capture, 'Current Duck public protocol contract changed')
  puts 'duck_racing: historical ready/begin and current last-ready startup, three rolls, settlement, race continuation, full/incremental replay and RNG OK'
end
