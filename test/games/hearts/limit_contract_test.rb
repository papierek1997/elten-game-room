require_relative '../../support/private_simulation'
require_relative '../../support/model_contract'
require_relative '../../../games/hearts_support/hearts_table'
require 'json'
include GameRoomTest::Assertions

path = File.expand_path('../../fixtures/contracts/v1/hearts.json', __dir__)
reference = JSON.parse(File.read(path))
game = GameRoomGames::HeartsTable.new
random = Random.new(reference.fetch('seed'))
original_hex = SecureRandom.method(:hex)
SecureRandom.define_singleton_method(:hex) do |n=16|
  Array.new(n) { random.rand(256).to_s(16).rjust(2,'0') }.join
end
begin
  env = GameRoomTest::PrivateSimulation.new_game(game:game, players:reference.fetch('players'),
    options:reference.fetch('options'), seed:reference.fetch('seed'))
  hashes = {}
  checkpoints = reference.fetch('steps') + [reference.fetch('final')]
  checkpoints.each_with_index do |expected,index|
    actual = GameRoomTest::ModelContract.checkpoint(env)
    assert_equal(expected.except('replay','action','action_actor'), actual.except('replay'), "Hearts input/legal/RNG boundary #{index} changed")
    copy = Marshal.load(Marshal.dump(env.replay))
    assert_equal(100,copy.state[:options].delete('score_limit'), 'Default rule is no longer the original 100 points')
    assert_equal(expected.fetch('replay'),GameRoomTest::ContractValues.digest(copy), "Only the explicit limit field may change old replay #{index}")
    hashes[index.to_s] = actual.fetch('replay')
    if expected['action']
      actor = expected.fetch('action_actor',expected.fetch('actor'))
      assert_equal(:ok,env.step(expected.fetch('action'),actor:actor))
    end
  end
  assert_equal(reference.fetch('events'),env.events, 'Serialized Hearts moves changed')
  if ARGV == ['--print']
    puts JSON.pretty_generate(hashes)
  else
    reviewed = JSON.parse(File.read(File.expand_path('../../fixtures/contracts/v2/hearts_limit.json',__dir__)))
    assert_equal(reviewed,hashes,'Reviewed explicit-limit checkpoint hashes changed')
    puts "PASS Hearts #{checkpoints.length} original checkpoints: only default-limit state differs; exact old replay, moves, actors, legal ordering and RNG retained"
  end
ensure
  SecureRandom.define_singleton_method(:hex,original_hex)
end
