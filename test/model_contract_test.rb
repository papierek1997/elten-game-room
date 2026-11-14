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
previous_quiz_v2 = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v2/quiz.json'), encoding: 'UTF-8'))
previous_quiz = corpus.fetch('cases').find { |item| item.fetch('game') == 'quiz' }
assert_equal(without_replay_hashes.call(previous_quiz), without_replay_hashes.call(previous_quiz_v2), 'Quiz wording must not replace the reference actions or RNG')
# Confirmed-answer cleanup adds only session-bound public receipt metadata.
# The separate semantic test checks exact fields and all four historical v2
# full replay hashes on detached copies; both earlier corpora stay unchanged.
quiz = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v3/quiz.json'), encoding: 'UTF-8'))
assert_equal(without_replay_hashes.call(previous_quiz_v2), without_replay_hashes.call(quiz), 'Quiz cleanup must not replace the reference actions or RNG')
# The Poker presentation adds per-viewer deal lines and separates shown hands.
# Its reviewed PR reference retains every old action, event, actor and RNG value.
poker = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v2/poker.json'), encoding: 'UTF-8'))
previous_poker = corpus.fetch('cases').find { |item| item.fetch('game') == 'poker' }
assert_equal(without_replay_hashes.call(previous_poker), without_replay_hashes.call(poker), 'Poker wording must not replace the reference actions or RNG')
# Categories adds pause, participant-departure and confirmed-cleanup metadata.
# A separate semantic regression verifies their exact values and reproduces
# both historical full replay hashes using detached copies.
previous_categories_v2 = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v2/categories.json'), encoding: 'UTF-8'))
categories = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v3/categories.json'), encoding: 'UTF-8'))
previous_categories = corpus.fetch('cases').find { |item| item.fetch('game') == 'categories' }
assert_equal(without_replay_hashes.call(previous_categories), without_replay_hashes.call(categories), 'Categories metadata must not replace the reference actions or RNG')
assert_equal(without_replay_hashes.call(previous_categories_v2), without_replay_hashes.call(categories),
  'The disabled per-category letter variant must not replace reference inputs, actions or RNG')
# Confirmed Scientific War reveals now retain public cleanup receipts across
# tricks. The semantic regression checks their exact historical commitments
# and reproduces every original full hash on a detached copy.
scientific_war = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v2/scientific_war.json'), encoding: 'UTF-8'))
previous_scientific_war = corpus.fetch('cases').find { |item| item.fetch('game') == 'scientific_war' }
assert_equal(without_replay_hashes.call(previous_scientific_war), without_replay_hashes.call(scientific_war), 'Scientific War cleanup must not replace the reference actions or RNG')
# The maintainer replaced Yahtzee's Joker/100-point rules outright. This trace
# contains no five-of-a-kind, so actions, scores, legal order and RNG must remain
# unchanged. Only the retired options and bonus bookkeeping leave the replay.
# Preserve the original corpus and inputs; the reviewed v2 records the new state.
yahtzee = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v2/yahtzee.json'), encoding: 'UTF-8'))
previous_yahtzee = corpus.fetch('cases').find { |item| item.fetch('game') == 'yahtzee' }
expected_yahtzee = without_replay_hashes.call(previous_yahtzee)
expected_yahtzee['session'] = previous_yahtzee.fetch('session').merge('options' => JSON.generate(
  JSON.parse(previous_yahtzee.fetch('session').fetch('options')).except('yahtzee_bonus', 'joker_rule')))
assert_equal(expected_yahtzee, without_replay_hashes.call(yahtzee), 'Yahtzee scoring cleanup must not replace the reference inputs, actions or RNG')
cases = corpus.fetch('cases').reject { |item| %w[tysiac quiz poker categories scientific_war yahtzee].include?(item.fetch('game')) } + [tysiac, quiz, poker, categories, scientific_war, yahtzee,
  JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v1/mille_bornes.json'), encoding: 'UTF-8'))]
# Bridge's shared private-hand integration changes ordinary hands from seat
# arrays to account-keyed hashes. All original actions, order and RNG remain.
bridge = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v2/bridge.json'), encoding: 'UTF-8'))
previous_bridge = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v1/bridge.json'), encoding: 'UTF-8'))
assert_equal(without_replay_hashes.call(previous_bridge), without_replay_hashes.call(bridge), 'Bridge hand storage must not replace the reference actions or RNG')
cases << bridge
cases << JSON.parse(File.read(File.join(__dir__, "fixtures/contracts/v1/mahjong-model.json"), encoding: "UTF-8"))
# The new-game presentation review changes history, not the moves, random
# stream, options, state or result. Replaying the original inputs on both
# versions confirmed that the complete replays agree with history removed.
# Keep the original fixture and override only the reviewed replay hashes.
new_games = %w[blackjack blackjack_dice bingo dice_poker liars_dice go roulette]
presentations = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v2/new_games_presentation.json'), encoding: 'UTF-8'))
assert((presentations.keys - new_games).empty?, 'Unexpected new-game presentation override')
(%w[bouillabaisse scopa mania_pisania] + new_games).each do |id|
  item = JSON.parse(File.read(File.join(__dir__, "fixtures/contracts/v1/#{id}.json"), encoding: 'UTF-8'))
  checkpoints = item.fetch('steps') + [item.fetch('final')]
  presentations.fetch(id, {}).each do |index, hash|
    position = Integer(index, 10)
    assert(position.between?(0, checkpoints.size - 1) && hash.match?(/\A[0-9a-f]{64}\z/),
      "Invalid #{id} presentation checkpoint #{index}")
    checkpoints.fetch(position)['replay'] = hash
  end
  cases << item
end
duck = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v1/duck_racing.json'), encoding: 'UTF-8'))
cash_auction = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v1/cash_auction.json'), encoding: 'UTF-8'))
cases << JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v1/billiards.json'), encoding: 'UTF-8'))
%w[kosciane balut french_tarot backgammon].each do |id|
  cases << JSON.parse(File.read(File.join(__dir__, "fixtures/contracts/v1/#{id}.json"), encoding:'UTF-8'))
end
expected_ids = GameRoomGames::CATALOG.ids.reject { |id| %w[axel_pong audio_ball].include?(id) }.sort
assert_equal(expected_ids, (cases.map { |item| item.fetch('game') } + [duck.fetch('game'), cash_auction.fetch('game')]).sort, 'corpus must explicitly cover every turn-based game')
assert((ARGV - expected_ids).empty?, 'unknown game requested for contract verification')
cases = cases.select { |item| ARGV.include?(item.fetch('game')) } unless ARGV.empty?
cases.each do |item|
  game = GameRoomGames::CATALOG.build(item.fetch('game'))
  random = Random.new(item.fetch('seed'))
  SecureRandom.define_singleton_method(:hex) { |n = 16| Array.new(n) { random.rand(256).to_s(16).rjust(2, '0') }.join }
  env = GameRoomTest::PrivateSimulation.new_game(game: game, players: item.fetch('players'), options: item.fetch('options'), seed: item.fetch('seed'))
  item.fetch('steps').each_with_index do |step, index|
    # Simultaneous local-input games have no single active turn. The corpus
    # still verifies that actor field, and separately names each input writer.
    expected = step.reject { |key, _| %w[action action_actor].include?(key) }
    assert_equal(expected, GameRoomTest::ModelContract.checkpoint(env), "#{game.id}, step #{index}: contract changed")
    assert_equal(:ok, env.step(step.fetch('action'), actor: step.fetch('action_actor', step.fetch('actor'))), "#{game.id}: action rejected")
  end
  assert_equal(item.fetch('final'), GameRoomTest::ModelContract.checkpoint(env), "#{game.id}: final checkpoint changed")
  assert_equal(item.fetch('events'), env.events, "#{game.id}: serialized history changed")
  puts "#{game.id}: #{item.fetch('steps').length} transitions, full/incremental replay, input ownership, action order and RNG OK"
end

if ARGV.empty? || ARGV.include?('cash_auction')
  require_relative 'support/cash_auction_model_contract'
  assert_equal(cash_auction, GameRoomTest::CashAuctionModelContract.capture, 'Cash Auction native public protocol contract changed')
  puts 'cash_auction: eight auctions, competing bids, questions, carryover, chest settlement, cold/incremental replay, legal order and RNG OK'
end

if ARGV.empty? || ARGV.include?('duck_racing')
  require_relative 'support/duck_model_contract'
  assert_equal(duck, GameRoomTest::DuckModelContract.capture(legacy: true), 'Historical Duck public protocol contract changed')
  current_duck = JSON.parse(File.read(File.join(__dir__, 'fixtures/contracts/v2/duck_racing.json'), encoding: 'UTF-8'))
  assert_equal(current_duck, GameRoomTest::DuckModelContract.capture, 'Current Duck public protocol contract changed')
  puts 'duck_racing: historical ready/begin and current last-ready startup, three rolls, settlement, race continuation, full/incremental replay and RNG OK'
end
