require_relative '../../../games/catalog'
require_relative '../../support/private_simulation'
require_relative '../../support/model_contract'
require_relative '../../support/historical_quiz'
include GameRoomTest::Assertions

reference = JSON.parse(File.read(File.join(__dir__, '../../fixtures/contracts/v2/quiz.json'), encoding:'UTF-8'))
current = JSON.parse(File.read(File.join(__dir__, '../../fixtures/contracts/v3/quiz.json'), encoding:'UTF-8'))
without_hashes = lambda do |item|
  item.merge('steps'=>item.fetch('steps').map { |step| step.reject { |key,_| key == 'replay' } },
    'final'=>item.fetch('final').reject { |key,_| key == 'replay' })
end
assert_equal(without_hashes.call(reference), without_hashes.call(current),
  'The versioned cleanup oracle must preserve every input, action, event, actor, legal-choice digest and RNG sample')
random = Random.new(reference.fetch('seed'))
SecureRandom.define_singleton_method(:hex) { |n = 16| Array.new(n) { random.rand(256).to_s(16).rjust(2,'0') }.join }
historical_game = GameRoomGames::QuizParty.new
historical_game.extend(GameRoomTest::HistoricalQuizQuestionProducer)
env = GameRoomTest::PrivateSimulation.new_game(game:historical_game,
  players:reference.fetch('players'), options:reference.fetch('options'), seed:reference.fetch('seed'))
old_stages = [*reference.fetch('steps'), reference.fetch('final')]
new_stages = [*current.fetch('steps'), current.fetch('final')]
old_stages.each_with_index do |expected, index|
  before = GameRoomTest::ContractValues.digest([env.session, env.events, env.replay])
  receipts = index < 3 ? {} : {'round-1-question-1'=>{
    'alice'=>'1ae612a8888d8877c65743c9a6a8b56d74a0229cde466f80d881919e11d9c0f6',
    'bob'=>'4b5120f12a230b37ce3177447eaac31cbde1ec2064ed65a6a3d6b8812b862aab'}}
  assert_equal({session_id:1, receipts:receipts}, env.replay.state.fetch(:answer_cleanup),
    "Quiz checkpoint #{index}: unexpected cleanup receipt, actor, session or premature confirmation")
  detached = env.replay.dup
  detached.state = env.replay.state.reject { |key,_| key == :answer_cleanup }
  assert_equal(expected.fetch('replay'), GameRoomTest::ContractValues.digest(detached),
    "Quiz checkpoint #{index}: full historical replay differs beyond cleanup metadata")
  actual = GameRoomTest::ModelContract.checkpoint(env)
  assert_equal(new_stages.fetch(index).reject { |key,_| key == 'action' }, actual,
    "Quiz checkpoint #{index}: current full oracle differs")
  assert_equal(expected.reject { |key,_| %w[action replay].include?(key) },
    actual.reject { |key,_| key == 'replay' }, "Quiz checkpoint #{index}: behavior changed")
  assert_equal(before, GameRoomTest::ContractValues.digest([env.session, env.events, env.replay]),
    'Detached historical comparison changed the actual model')
  assert_equal(:ok, env.step(expected.fetch('action'), actor:expected.fetch('actor'))) if expected.key?('action')
end
assert_equal(reference.fetch('session'), env.session, 'Historical session changed')
assert_equal(reference.fetch('events'), env.events, 'Historical serialized events changed')
puts 'PASS Quiz cleanup oracle: exact receipts, four detached historical full hashes, unchanged actions/session/events/actor/legal/RNG'
