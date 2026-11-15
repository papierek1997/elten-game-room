require_relative '../../support/private_simulation'
require_relative '../../support/model_contract'
require_relative '../../../games/kosciane'
include GameRoomTest::Assertions

root = File.expand_path('../../..', __dir__)
reference = JSON.parse(File.read(File.join(root, 'test/fixtures/contracts/v1/kosciane.json')))
previous = JSON.parse(File.read(File.join(root, 'test/fixtures/contracts/v3/new_games_feedback.json'))).fetch('kosciane')
current = JSON.parse(File.read(File.join(root, 'test/fixtures/contracts/v4/dice_general_feedback.json'))).fetch('kosciane')
original_hex = SecureRandom.method(:hex)
begin
  random = Random.new(reference.fetch('seed'))
  SecureRandom.define_singleton_method(:hex) { |n=16| Array.new(n) { random.rand(256).to_s(16).rjust(2, '0') }.join }
  env = GameRoomTest::PrivateSimulation.new_game(game: GameRoomGames::Kosciane.new,
    players: reference.fetch('players'), options: reference.fetch('options'), seed: reference.fetch('seed'))
  changed = []
  (reference.fetch('steps') + [reference.fetch('final')]).each_with_index do |step, index|
    actual = GameRoomTest::ModelContract.checkpoint(env)
    expected = step.reject { |key, _| %w[action action_actor].include?(key) }
    assert_equal(expected.reject { |key, _| key == 'replay' }, actual.reject { |key, _| key == 'replay' },
      'Cue feedback changed inputs, ownership, legal action order or RNG')
    restored = Marshal.load(Marshal.dump(env.replay))
    restored.history.select { |entry| entry.kind == :score }.each do |entry|
      assert(entry.value.to_s.match?(/\Akosciane_column_[1-6](?:_(?:win[12]|lose3|draw2))?\z/), 'Unexpected score cue')
      entry.value = nil
    end
    old_hash = previous.fetch(index.to_s, expected.fetch('replay'))
    assert_equal(old_hash, GameRoomTest::ContractValues.digest(restored),
      'More than score cue metadata changed: preserve the full original model, history text and accepted events')
    assert_equal(current.fetch(index.to_s, old_hash), actual.fetch('replay'), 'The reviewed cue metadata changed')
    changed << index.to_s if actual.fetch('replay') != old_hash
    if step['action']
      assert_equal(:ok, env.step(step['action'], actor: step.fetch('action_actor', step.fetch('actor'))))
    end
  end
  assert_equal(current.keys, changed, 'The override must name exactly the changed checkpoints')
ensure
  SecureRandom.define_singleton_method(:hex, original_hex)
end
puts 'PASS Dice General feedback: 13 cue-only changes reproduce every original full contract hash'
