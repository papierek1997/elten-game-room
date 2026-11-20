require_relative '../../../games/catalog'
require_relative '../../support/private_simulation'
require_relative '../../support/model_contract'
include GameRoomTest::Assertions
reference = JSON.parse(File.read(File.join(__dir__, '../../fixtures/contracts/v2/poker.json')))
hashes = JSON.parse(File.read(File.join(__dir__, '../../fixtures/contracts/v3/poker_bot_evidence.json')))
env = GameRoomTest::PrivateSimulation.new_game(game: GameRoomGames::Poker.new,
  players: reference.fetch('players'), options: reference.fetch('options'), seed: reference.fetch('seed'))
stages = [*reference.fetch('steps'), reference.fetch('final')]
assert_equal(stages.size.times.map(&:to_s), hashes.keys, 'Unexpected evidence checkpoints')
stages.each_with_index do |expected, index|
  before = GameRoomTest::ContractValues.digest(env.replay)
  detached = Marshal.load(Marshal.dump(env.replay))
  detached.history.each do |entry|
    if entry.field == 'poker_bet'
      assert(entry.key.start_with?('bet:') && entry.kind == :game)
      assert_equal(%w[action call hand paid pot raise_by street], entry.value.keys.sort)
      assert(entry.value.reject { |key,_| key == 'action' }.values.all? { |value| value.is_a?(Integer) && value >= 0 })
      event = env.events.find { |record| record['id'] == entry.event_id || record['__id'] == entry.event_id }
      assert_equal(event.fetch('value').split('|').first, entry.value.fetch('action'))
      entry.field, entry.value = nil, nil
    elsif entry.field == 'poker_showdown'
      assert(entry.key.start_with?('showdown_hand:') && entry.kind == :game)
      assert_equal(%w[category hand variant], entry.value.keys.sort)
      assert(entry.value['category'].is_a?(Integer) && entry.value['category'].between?(0,8))
      entry.field, entry.value = nil, nil
    end
  end
  assert_equal(expected.fetch('replay'), GameRoomTest::ContractValues.digest(detached),
    "Poker checkpoint #{index}: rule state, history or text differs beyond public bot evidence")
  actual = GameRoomTest::ModelContract.checkpoint(env)
  assert_equal(hashes.fetch(index.to_s), actual.fetch('replay'))
  assert_equal(expected.reject { |key,_| %w[action replay].include?(key) }, actual.reject { |key,_| key == 'replay' })
  assert_equal(before, GameRoomTest::ContractValues.digest(env.replay), 'Detached comparison changed the game')
  assert_equal(:ok, env.step(expected.fetch('action'), actor: expected.fetch('actor'))) if expected['action']
end
assert_equal(reference.fetch('events'), env.events)
assert_equal(reference.fetch('session'), env.session)
puts 'PASS Poker public evidence: 17 original full hashes reproduced, unchanged rules/text/actions/events/legal order/RNG and exact typed fields'
