require_relative '../../support/cash_auction_model_contract'
include GameRoomTest::Assertions

root = File.expand_path('../../..', __dir__)
original = JSON.parse(File.read(File.join(root, 'test/fixtures/contracts/v1/cash_auction.json'), encoding: 'UTF-8'))
feedback = JSON.parse(File.read(File.join(root, 'test/fixtures/contracts/v2/cash_auction_feedback.json'), encoding: 'UTF-8'))
contract = GameRoomTest::CashAuctionModelContract
checkpoint = contract.method(:checkpoint)
snapshots = []
begin
  contract.define_singleton_method(:checkpoint) do |match, random|
    replay = match.replay
    restored = Marshal.load(Marshal.dump(replay))
    bank = match.game.send(:question_bank, replay.state.fetch(:options))
    restored.history.each do |entry|
      next unless entry.key == "cash-auction:#{entry.event_id}" && entry.text&.start_with?('Category: ')

      bank.categories.each do |category|
        current = "Category: #{bank.category_label(category, include_set: true)}. "
        historical = "Category: #{bank.category_label(category)}. "
        entry.text = entry.text.sub(current, historical)
      end
    end
    snapshots << GameRoomTest::ContractValues.digest(restored)
    checkpoint.call(match, random)
  end
  actual = contract.capture
ensure
  contract.define_singleton_method(:checkpoint, checkpoint)
end

assert_equal(original.fetch('steps').map { |step| step.fetch('replay') }, snapshots,
  'Only set-qualified category history may differ: retain the complete old state and history')
without_hashes = ->(item) { item.merge('steps' => item.fetch('steps').map { |step| step.except('replay') }) }
assert_equal(without_hashes.call(original), without_hashes.call(actual),
  'Category feedback changed inputs, accepted events, legal action order, actors or RNG')
changed = actual.fetch('steps').each_index.select do |index|
  original.fetch('steps')[index]['replay'] != actual.fetch('steps')[index]['replay']
end.map(&:to_s)
assert_equal(changed, feedback.keys)
feedback.each { |index, hash| assert_equal(hash, actual.fetch('steps').fetch(Integer(index, 10)).fetch('replay')) }
puts 'PASS Cash Auction category feedback: every original full hash restored; all actions, state, ownership and RNG unchanged'
