require_relative '../../support/cash_auction'

module CashAuctionModelTest
  extend GameRoomTest::Assertions
  F = CashAuctionFixture::Match
  module_function

  def run
    concurrent_bids_and_calls
    answered_choices_and_carryover
    all_in_elimination
    eight_round_match_and_owned_history
    eight_round_tie
    chests_change_result
    eliminated_chest_owner
    forged_records
    native_clock_and_stale_sessions
    bot_ignores_hidden_answers
    puts 'Cash Auction model: actual seeded plans, concurrent bids/timer scopes, delayed ABCD questions, payout/carryover/elimination, eight rounds/tie, chest-first results, cold replay, strict native records and answer-independent bot RNG passed.'
  end

  def no_fold_change(fixture)
    before = fixture.replay
    yield
    after = fixture.replay
    assert_equal(before.state, after.state, 'Rejected input changed the model')
    assert_equal(before.history, after.history, 'Rejected input wrote history')
    assert_equal(before.accepted_events, after.accepted_events, 'Rejected input became accepted')
  end

  def denied(fixture, selection, actor:, statuses: [:invalid])
    view = fixture.replay
    before = Marshal.dump(view)
    status, plan = fixture.plan(selection, actor: actor, view: view)
    assert(statuses.include?(status), "Unexpected refusal #{status} for #{selection.inspect}")
    assert_equal(nil, plan)
    assert_equal(before, Marshal.dump(view), 'action_for mutated its supplied replay')
  end

  def concurrent_bids_and_calls
    f = F.new
    f.begin_round
    assert_equal([990] * 4, f.replay.state[:cash])
    original = f.replay
    selections = [f.bid_selection('Alice', 100, view: original), f.bid_selection('Bob', 200, view: original)]
    plans = selections.zip(%w[Alice Bob]).map do |selection, actor|
      status, plan = f.plan(selection, actor: actor, view: original)
      assert_equal(:ok, status)
      plan
    end
    f.now += 1
    f.append_plan(plans[0], actor: 'Alice')
    f.now += 1
    f.append_plan(plans[1], actor: 'Bob')
    current = f.replay
    assert_equal([890, 790, 990, 990], current.state[:cash])
    assert_equal(340, current.state[:pot])
    assert_equal(4000, current.state[:cash].sum + current.state[:pot])
    assert(f.game.concurrent_session_input?(original, current, selections[1]))
    assert_equal(nil, current.current_player, 'A simultaneous auction invented one current player')
    assert_equal(nil, current.state[:question])
    denied(f, {'kind'=>'automatic', 'action'=>'question'}, actor: 'Alice')
    denied(f, f.bid_selection('Carol', 200), actor: 'Carol', statuses: [:invalid_bet])
    denied(f, f.bid_selection('Mallory', 250), actor: 'Mallory', statuses: [:not_your_turn])
    deadline = current.state[:auction_deadline]
    calls_and_fresh_deadline(f, current, deadline)
  end

  def calls_and_fresh_deadline(f, old, deadline)
    old_history = Marshal.dump(f.replay.history)
    first = f.game.timer_announcements(old, 'Alice', now: deadline - 4)
    second = f.game.timer_announcements(old, 'Alice', now: deadline - 2)
    assert_equal(['auction_call_low', :skip_on_reconstruction], first.first.last(2))
    assert_equal(['auction_call_high', :skip_on_reconstruction], second.first.last(2))
    assert(first.first[0] != second.first[0])
    assert_equal(first, f.game.timer_announcements(old, 'Bob', now: deadline - 3))
    assert_equal([], f.game.timer_announcements(old, 'Alice', now: deadline))
    assert_equal(old_history, Marshal.dump(f.replay.history), 'Local countdown wrote history')
    f.now = deadline
    status, stale_close = f.plan({'kind'=>'automatic', 'action'=>'auction_closed'}, view: old)
    assert_equal(:ok, status)
    f.now = deadline - 3
    f.bid('Carol', 250)
    fresh = f.replay
    assert_equal(f.now + 6, fresh.state[:auction_deadline])
    assert_equal([], f.game.timer_announcements(fresh, 'Alice', now: f.now + 1))
    changed = f.game.timer_announcements(fresh, 'Alice', now: f.now + 2)
    assert(first.first[0] != changed.first[0], 'New bid reused the old countdown token')
    f.now = deadline
    no_fold_change(f) { stale_close.events.each { |command| f.materialize(command) } }
    f.close_auction
    assert_equal(:question_pending, f.replay.state[:phase])
    assert_equal(nil, f.replay.state[:question])
    assert_equal(0, f.events.count { |event| event['action'] == 'question' })
    f.reveal_question
    assert_equal('Carol', f.replay.current_player)
    assert_equal(:answering, f.replay.state[:phase])
  end

  def answered_choices_and_carryover
    4.times do |index|
      f = F.new
      f.begin_round
      f.now += 1
      f.bid('Bob', 100)
      f.close_auction
      f.reveal_question(seed: f.question_seed_for_index(index))
      view = f.replay
      spec = f.game.surface_spec(view, 'Bob')
      assert_equal(:single_choice, spec.mode)
      assert_equal(%w[0 1 2 3], spec.options.map(&:value))
      assert_equal(%w[A B C D], spec.options.map { |option| option.label[0] })
      assert_equal(false, spec.read_only)
      assert_equal(true, f.game.surface_spec(view, 'Alice').read_only)
      denied(f, {'kind'=>'question', 'action'=>'submit', 'question_id'=>spec.id, 'answer'=>index.to_s}, actor: 'Alice')
      denied(f, {'kind'=>'question', 'action'=>'submit', 'question_id'=>spec.id, 'answer'=>'4'}, actor: 'Bob')
      f.now += 1
      f.answer('Bob', index)
      assert_equal([990, 1030, 990, 990], f.replay.state[:cash])
      assert_equal(0, f.replay.state[:pot])
      assert_equal(:correct_answer, f.replay.history.last.kind)
    end
    f = F.new
    f.begin_round
    f.now += 1
    f.bid('Alice', 100)
    f.close_auction
    f.reveal_question
    wrong = (f.replay.state[:question][:correct_index] + 1) % 4
    f.now += 1
    f.answer('Alice', wrong)
    assert_equal(140, f.replay.state[:pot])
    assert_equal(:wrong_answer, f.replay.history.last.kind)
    f.begin_round
    assert_equal(180, f.replay.state[:pot], 'Wrong-answer pool did not survive the next ante')
    f.now += 1
    f.bid('Bob', 200)
    f.close_auction
    f.reveal_question
    f.now += 1
    f.answer_correct('Bob')
    assert_equal(1160, f.replay.state[:cash][1])
    assert_equal(4000, f.replay.state[:cash].sum)
  end

  def all_in_elimination
    f = F.new
    f.begin_round
    f.now += 1
    f.bid('Alice', 100)
    f.now += 1
    f.bid('Alice', 'A')
    assert_equal([0, 990], [f.replay.state[:cash][0], f.replay.state[:contributions][0]])
    assert_equal(1030, f.replay.state[:pot])
    assert_equal(:question_pending, f.replay.state[:phase])
    f.reveal_question
    wrong = (f.replay.state[:question][:correct_index] + 1) % 4
    f.now += 1
    f.answer('Alice', wrong)
    assert_equal(true, f.replay.state[:eliminated][0])
    f.begin_round
    assert_equal(1060, f.replay.state[:pot])
    assert_equal([], f.game.legal_actions(f.replay, 'Alice', context: f.context))
    assert(!f.game.active_actors(f.replay).include?('Alice'))
    denied(f, {'kind'=>'question', 'action'=>'submit', 'question_id'=>'ignored', 'answer'=>'1'}, actor: 'Alice', statuses: [:not_your_turn])
    assert_equal(4000, f.replay.state[:cash].sum + f.replay.state[:pot])
  end

  def ordinary_winning_round(f, actor)
    f.begin_round
    f.now += 1
    f.bid(actor, 1)
    f.close_auction
    f.reveal_question(seed: f.replay.state[:round])
    f.now += 1
    f.answer_correct(actor)
  end

  def eight_round_match_and_owned_history
    f = F.new
    8.times { ordinary_winning_round(f, 'Alice') }
    current = f.replay
    assert_equal([:finished, 8, 'Alice', false], [current.state[:phase], current.state[:completed_rounds], current.winner, current.draw])
    assert_equal([1240, 920, 920, 920], current.state[:cash])
    assert_equal(48, current.accepted_events.length)
    cold = GameRoomGames::CashAuction.new.replay(f.session, f.events, f.repository)
    assert_equal(current, cold, 'Full eight-round cold replay differed')
    original = Marshal.dump(f.events)
    current.state[:cash][0] = -999
    current.state[:question][:choices][0].replace('poisoned returned answer')
    current.history.first.text = 'poisoned returned history'
    assert_equal(cold, f.replay, 'Returned replay aliased a checkpoint')
    assert_equal(original, Marshal.dump(f.events), 'Replay mutated its source events')
    denied(f, {'kind'=>'automatic', 'action'=>'wheel'}, actor: 'Alice', statuses: [:finished])
  end

  def eight_round_tie
    f = F.new
    8.times { f.begin_round; f.close_auction }
    assert_equal([8, :drawing], f.replay.state.values_at(:completed_rounds, :phase))
    assert_equal(nil, f.replay.winner)
    assert_equal(0, f.events.count { |event| event['action'] == 'question' })
    f.begin_round
    assert_equal(9, f.replay.state[:round])
    assert_equal(f.players, f.game.active_actors(f.replay), 'Extra round excluded another active seat')
    f.now += 1
    f.bid('Bob', 1)
    f.close_auction
    f.reveal_question
    f.now += 1
    f.answer_correct('Bob')
    assert_equal([:finished, 'Bob', 9], [f.replay.state[:phase], f.replay.winner, f.replay.state[:completed_rounds]])
    assert_equal(4000, f.replay.state[:cash].sum)
  end

  def chest_match(all_in: false)
    f = F.new
    f.begin_round(chest: true)
    f.now += 1
    f.bid('Alice', all_in ? 'A' : 1)
    f.close_auction unless all_in
    assert_equal([1, 0, 0, 0], f.replay.state[:chests])
    assert_equal(:drawing, f.replay.state[:phase])
    assert_equal(0, f.events.count { |event| event['action'] == 'question' })
    7.times { ordinary_winning_round(f, 'Bob') }
    assert_equal(:opening_chests, f.replay.state[:phase])
    assert_equal(nil, f.replay.winner, 'Result was published before the owned chest')
    f
  end

  def chests_change_result
    f = chest_match
    before = f.replay
    assert(before.state[:cash][1] > before.state[:cash][0])
    f.now += 1
    f.open_chest('Alice', reward: 10_000)
    assert_equal([:finished, 'Alice'], [f.replay.state[:phase], f.replay.winner])
    assert_equal([0, 0, 0, 0], f.replay.state[:chests])
    assert_equal(14_000, f.replay.state[:cash].sum + f.replay.state[:pot])
    assert_equal(f.replay, GameRoomGames::CashAuction.new.replay(f.session, f.events, f.repository))
  end

  def eliminated_chest_owner
    f = chest_match(all_in: true)
    assert_equal(true, f.replay.state[:eliminated][0])
    assert(f.game.active_actors(f.replay).include?('Alice'), 'Eliminated owner could not open a chest')
    f.now += 1
    f.open_chest('Alice', reward: 10_000)
    result = f.replay
    assert_equal(true, result.state[:eliminated][0])
    assert_equal(10_000, result.state[:cash][0])
    assert_equal('Bob', result.winner, 'Chest winnings revived an eliminated seat for the result')
  end

  def forged_records
    f = F.new
    selection = f.game.automatic_action(f.replay, 'Alice', context: f.context)
    status, plan = f.plan(selection)
    assert_equal(:ok, status)
    command = plan.events.first
    value = command.random_request.dig('recipe', 'template').sub('{seed}', '0' * 31 + '1')
    no_fold_change(f) { f.append_raw(action: 'wheel', value: value) }
    [nil, 0, -1, '1'].each do |id|
      no_fold_change(f) { f.append_raw(action: 'wheel', value: value, id: id, '__server_random'=>command.random_request) }
    end
    [nil, 0, -1, '100', '100junk', 100.5, GameRoomSessionClock::MAX_EVENT_TIME + 1].each do |time|
      no_fold_change(f) { f.append_raw(action: 'wheel', value: value, created_at: time,
        '__server_random'=>command.random_request, 'sequence'=>101) }
    end
    malformed = Marshal.load(Marshal.dump(command.random_request))
    malformed['recipe']['seats'] = [1]
    no_fold_change(f) { f.append_raw(action: 'wheel', value: value, '__server_random'=>malformed) }
    no_fold_change(f) { f.append_raw(action: 'wheel', value: value, actor: 'Bob', '__server_random'=>command.random_request) }
    f.append_plan(plan)
    first = f.replay.accepted_events.last
    no_fold_change(f) { f.append_raw(action: 'auction_start', value: '1', id: first['id']) }
    no_fold_change(f) { f.append_raw(action: 'auction_start', value: '1', created_at: f.native_time - 1) }
    f.now = f.replay.state[:resume_at]
    f.automatic
    round = f.replay.state[:round]
    ['-1', '0', '100000000', '1x', '1|1', '1' * 129].each do |amount|
      no_fold_change(f) { f.append_raw(action: 'bid', value: "#{round}|#{amount}", actor: 'Bob') }
    end
    no_fold_change(f) { f.append_raw(action: 'bid', value: "#{round}|100", actor: 'Mallory') }
    f.now += 1
    f.bid('Bob', 100)
    no_fold_change(f) { f.append_raw(action: 'bid', value: "#{round}|99", actor: 'Carol') }
    f.close_auction
    no_fold_change(f) { f.append_raw(action: 'question', value: "#{round}|#{f.replay.state[:bid_revision]}|#{'0' * 32}") }
    f.reveal_question
    no_fold_change(f) { f.append_raw(action: 'answer', value: "#{round}|0|0", actor: 'Bob') }
  end

  def native_clock_and_stale_sessions
    f = F.new(epoch_shift: 500)
    f.begin_round
    assert_equal(603, f.replay.state[:time])
    assert_equal(609, f.replay.state[:auction_deadline])
    assert_equal(103, f.events.last['created_at'])
    f.now += 1
    f.bid('Bob', 100)
    assert_equal(610, f.replay.state[:auction_deadline])
    other = F.new(game_id: 'cash-auction-other')
    other.begin_round
    old_selection = f.bid_selection('Carol', 150)
    assert(!other.game.concurrent_session_input?(f.replay, other.replay, old_selection))
    denied(other, old_selection, actor: 'Carol')
  end

  def bot_ignores_hidden_answers
    f = F.new
    f.begin_round
    f.now += 1
    f.bid('Bob', 100)
    f.close_auction
    f.reveal_question
    original = f.replay
    before = Marshal.dump(original)
    owned = f.game.bot_observation(original, 'Bob')
    owned[:players][0].replace('changed observer name')
    owned[:cash][0] = -1
    owned[:question][:prompt].replace('changed public question')
    owned[:question][:choices][0].replace('changed public answer')
    assert_equal(before, Marshal.dump(original), 'Bot observation aliases its replay')
    altered = Marshal.load(Marshal.dump(original))
    altered.state[:question][:correct_index] = (original.state[:question][:correct_index] + 1) % 4
    altered.state[:question][:used] = ['unrelated-future-id']
    altered.state[:future_answer] = 'private future data'
    assert_equal(f.game.bot_observation(original, 'Bob'), f.game.bot_observation(altered, 'Bob'))
    actions = f.game.legal_actions(original, 'Bob', context: f.context)
    assert_equal(actions, f.game.legal_actions(altered, 'Bob', context: f.context))
    picked = []
    12.times do |seed|
      randoms = [GameRoomRandom::SeededSource.new(seed), GameRoomRandom::SeededSource.new(seed)]
      choices = [original, altered].each_with_index.map do |view, i|
        GameRoomBots.choose(f.game.bot_strategy, {actions: actions, actor: 'Bob', random_source: randoms[i],
          game: f.game, replay: view, context: f.context}) { f.game.bot_observation(view, 'Bob') }
      end
      assert_equal(choices[0], choices[1], 'Bot used a hidden correct answer')
      assert_equal(randoms[0].roll(count: 4, sides: 100).values, randoms[1].roll(count: 4, sides: 100).values, 'Hidden answer changed the following RNG stream')
      picked << choices[0]['answer']
    end
    assert(picked.uniq.length > 1, 'Answer strategy did not use the permitted random choice')
  end
end
CashAuctionModelTest.run if $PROGRAM_NAME == __FILE__
