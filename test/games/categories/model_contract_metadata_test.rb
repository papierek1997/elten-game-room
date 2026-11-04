require_relative '../../../games/catalog'
require_relative '../../support/private_simulation'
require_relative '../../support/model_contract'
include GameRoomTest::Assertions

# The old full checkpoint is still the reference, not a newly generated digest.
# Only the approved pause/departure/cleanup bookkeeping may differ at this opening.
corpus = JSON.parse(File.read(File.join(__dir__, '../../fixtures/contracts/v1/histories.json'), encoding: 'UTF-8'))
item = corpus.fetch('cases').find { |entry| entry.fetch('game') == 'categories' }
game = GameRoomGames::Categories.new
random = Random.new(item.fetch('seed'))
SecureRandom.define_singleton_method(:hex) { |n = 16| Array.new(n) { random.rand(256).to_s(16).rjust(2, '0') }.join }
env = GameRoomTest::PrivateSimulation.new_game(game: game, players: item.fetch('players'),
  options: item.fetch('options'), seed: item.fetch('seed'))
item.fetch('steps').each { |step| assert_equal(:ok, env.step(step.fetch('action'), actor: step.fetch('actor'))) }

metadata = {
  resume_at: 0,
  round_player_order: ['Bob'],
  departed_players: [],
  roster_revision: 0,
  judge_queue: %w[Alice Bob],
  permanent_judge: 'Alice'
}
assert_equal(metadata, env.replay.state.slice(*metadata.keys), 'New opening metadata changed')
assert_equal({session_id: 1, receipts: {}}, env.replay.state.fetch(:answer_cleanup),
  'Opening cleanup receipt must identify this session and contain no confirmations')
before = GameRoomTest::ContractValues.digest(env.replay)
assert_equal({}, env.replay.state.fetch(:category_letters), 'Ordinary mode has per-category letters')
assert_equal(false, env.replay.state.fetch(:options).fetch('separate_letters'), 'Ordinary mode changed')
without_variant = env.replay.dup
without_variant.state = env.replay.state.reject { |key, _value| key == :category_letters }
without_variant.state[:options] = env.replay.state.fetch(:options).reject { |key, _value| key == 'separate_letters' }
previous_v2 = JSON.parse(File.read(File.join(__dir__, '../../fixtures/contracts/v2/categories.json'), encoding: 'UTF-8'))
assert_equal(previous_v2.fetch('final').fetch('replay'), GameRoomTest::ContractValues.digest(without_variant),
  'Categories changed beyond the two declared disabled-variant fields since the complete v2 checkpoint')
without_cleanup = env.replay.dup
without_cleanup.state = env.replay.state.reject { |key, _value| [:answer_cleanup, :category_letters].include?(key) }
without_cleanup.state[:options] = env.replay.state.fetch(:options).reject { |key, _value| key == 'separate_letters' }
assert_equal('4d70727b42f55fb285d284c0193d8662255b36ae4ec48efd1f8554e56b707d78',
  GameRoomTest::ContractValues.digest(without_cleanup), 'Categories changed more than the approved cleanup metadata since v2')
legacy = without_cleanup.dup
legacy.state = without_cleanup.state.reject { |key, _value| metadata.key?(key) }
assert_equal(item.fetch('final').fetch('replay'), GameRoomTest::ContractValues.digest(legacy),
  'Categories changed more than the seven approved opening state fields')
assert_equal(before, GameRoomTest::ContractValues.digest(env.replay), 'Comparison mutated the real replay')
ordinary_session = env.session.merge('options'=>JSON.generate(JSON.parse(env.session.fetch('options')).reject { |key,_| key == 'separate_letters' }))
assert_equal(item.fetch('session'), ordinary_session, 'Opening session changed beyond the disabled variant option')
assert_equal(item.fetch('events'), env.events, 'Opening action or serialized history changed')
checkpoint = GameRoomTest::ModelContract.checkpoint(env)
current = JSON.parse(File.read(File.join(__dir__, '../../fixtures/contracts/v3/categories.json'), encoding: 'UTF-8'))
assert_equal(current.fetch('final'), checkpoint, 'The current complete checkpoint is not covered by the approved metadata comparison')
assert_equal(item.fetch('final').reject { |key, _value| key == 'replay' },
  checkpoint.reject { |key, _value| key == 'replay' }, 'Opening actor, legal choices or RNG changed')
puts 'PASS Categories contract: exact cleanup metadata and detached v2/v1 full replay; unchanged session, events, actor, legal choices and RNG'
