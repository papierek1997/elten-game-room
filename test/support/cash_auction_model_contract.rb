require_relative 'cash_auction'
require_relative 'contract_values'

module GameRoomTest
  module CashAuctionModelContract
    extend Assertions
    module_function

    # The native clock and random-request evidence cannot be represented by
    # the event-count clock of the ordinary standalone simulation.
    def capture
      original_uuid = SecureRandom.method(:uuid)
      identity = 0
      SecureRandom.define_singleton_method(:uuid) { '00000000-0000-4000-8000-%012x' % (identity += 1) }
      match = CashAuctionFixture::Match.new(players: %w[Alice Bob], options: {'starting_points'=>2000}, game_id: 'cash-auction-contract')
      random = Random.new(137)
      steps = [checkpoint(match, random)]
      8.times do |round|
        match.begin_round(chest: round == 7)
        steps << checkpoint(match, random)
        match.bid('Alice', 100)
        steps << checkpoint(match, random)
        match.bid('Bob', 200)
        steps << checkpoint(match, random)
        match.pass('Alice')
        steps << checkpoint(match, random)
        match.close_auction
        steps << checkpoint(match, random)
        next if round == 7

        match.reveal_question(seed: random.rand(1 << 128))
        steps << checkpoint(match, random)
        match.answer_correct('Bob')
        steps << checkpoint(match, random)
      end
      assert_equal(:opening_chests, match.replay.state[:phase])
      match.open_chest('Bob', reward: 100)
      steps << checkpoint(match, random)
      assert_equal('Bob', match.replay.winner)
      {'game'=>'cash_auction', 'seed'=>137, 'players'=>match.players, 'session'=>match.session,
        'steps'=>steps, 'events'=>match.events}
    ensure
      SecureRandom.define_singleton_method(:uuid, original_uuid) if original_uuid
    end

    def checkpoint(match, random)
      before = ContractValues.digest([match.session, match.events])
      replay = match.replay
      cold = match.game.build_session_game.replay(match.session, match.events, match.repository)
      assert_equal(ContractValues.canonical(cold), ContractValues.canonical(replay), 'Cash Auction cold/incremental mismatch')
      assert_equal(match.events, replay.accepted_events, 'Cash Auction protocol rejected a generated event')
      unknown = {'id'=>2_000_000_000, 'actor'=>'Unknown', 'action'=>'unknown', 'value'=>'', 'created_at'=>match.native_time}
      refused = match.game.replay(match.session, match.events + [unknown], match.repository)
      assert_equal(ContractValues.canonical(replay), ContractValues.canonical(refused), 'Unknown Cash Auction event changed replay')
      assert_equal(before, ContractValues.digest([match.session, match.events]), 'Cash Auction replay changed its inputs')
      actions = match.players.to_h { |actor| [actor, match.game.legal_actions(replay, actor, context: match.context)] }
      future = random.dup
      {'events'=>match.events.length, 'replay'=>ContractValues.digest(replay),
        'legal'=>ContractValues.digest(actions), 'rng'=>Array.new(8) { future.rand(1 << 128) }}
    end
  end
end
