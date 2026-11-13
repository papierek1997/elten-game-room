require_relative '../../support/cash_auction_native'

include GameRoomTest::Assertions

fixtures = []
begin
  f = CashAuctionNative::Fixture.new
  fixtures << f
  snapshot = Marshal.dump(f.state)
  assert_equal([:game, 0], f.layout.focus_location)
  assert(f.input.is_a?(EditBox), 'Auction did not start in the native bid field')
  assert_equal(0, f.form.index, 'The bid field did not receive index-zero focus')
  assert_equal(2, f.surface.fields.length, 'Auction invented a second submit control')
  assert(f.surface.fields[1].is_a?(Button), 'Pass is not a native button')
  f.type('125')
  f.press(13)
  bid = f.actions.last
  assert_equal('question', bid['kind'])
  assert_equal('submit', bid['action'])
  assert_equal('125', bid['answer'])
  assert_equal('cash-auction:native-cash-test:bid:1', bid['question_id'])
  assert(bid['_text_input'].length == 2 && bid['_text_input'].all? { |part| part.is_a?(Integer) },
    'The bid lost its local edit-generation receipt')
  assert_equal('125', f.input.text, 'Enter cleared a bid before acceptance')
  assert(f.surface.action_accepted(bid), 'Accepted own input did not clear its matching control')
  assert_equal('', f.input.text)
  assert_equal([0, 0], [f.input.index, f.input.check])
  f.type('A')
  f.press(13)
  assert_equal('A', f.actions.last['answer'], 'Native A Enter did not capture all-in text')
  assert_equal('submit', f.actions.last['action'])
  f.press(9)
  assert(f.form.fields[f.form.index].equal?(f.surface.fields[1]), 'Tab did not reach Pass')
  f.press(13)
  assert_equal('pass', f.actions.last['action'], 'Pass Enter submitted the bid instead')
  assert_equal('cash-auction:native-cash-test:bid:1', f.actions.last['question_id'])
  assert_equal(snapshot, Marshal.dump(f.state), 'Native bid/pass input mutated the model')
  assert_equal([], f.replay.accepted_events, 'Native controls wrote game events')

  invalid = CashAuctionNative::Fixture.new
  fixtures << invalid
  invalid.type('bad')
  invalid.press(13)
  refused = invalid.actions.last
  assert_equal(false, invalid.surface.action_rejected(refused, :invalid_bet))
  assert_equal('bad', invalid.input.text, 'Validation refusal erased the draft')
  invalid.type('250')
  invalid.press(13)
  assert_equal('250', invalid.actions.last['answer'], 'Correcting rejected input failed')
  invalid.surface.action_accepted(invalid.actions.last)
  invalid.type('as')
  assert_equal('as', invalid.input.text, 'Game shortcuts consumed bid-field letters')
  assert_equal([], invalid.shortcut_actions, 'Editable text invoked a game shortcut')
  invalid.press(0x24)
  invalid.press(0x27, modifiers: [0x10])
  assert(invalid.input.index != invalid.input.check, 'Native text selection stopped working')

  concurrent = CashAuctionNative::Fixture.new
  fixtures << concurrent
  concurrent.type('340')
  concurrent.press(0x24)
  concurrent.press(0x27)
  before_selection = [concurrent.input.index, concurrent.input.check]
  before_id = concurrent.surface.state['question_id']
  before_decision = concurrent.game.required_decision_key(concurrent.replay, 'Alice')
  assert(GameRoomCashAuction::Rules.bid!(concurrent.state, 1, 200, now: 101, revision: 1), 'Fixture refused the concurrent bid')
  concurrent.refresh
  assert_equal('340', concurrent.input.text, 'Another player bid erased local input')
  assert_equal(before_selection, [concurrent.input.index, concurrent.input.check], 'A bid update moved the text cursor')
  assert_equal(before_id, concurrent.surface.state['question_id'], 'Another bid changed the round input identity')
  assert_equal(before_decision, concurrent.game.required_decision_key(concurrent.replay, 'Alice'))
  assert_equal([:game, 0], concurrent.layout.focus_location, 'A bid update stole input focus')
  concurrent.press(13)
  old_receipt = concurrent.actions.last
  concurrent.type('500')
  assert_equal(false, concurrent.surface.action_accepted(old_receipt), 'An old ACK cleared a newer bid')
  assert_equal('500', concurrent.input.text)
  concurrent.press(13)
  own_bid = concurrent.actions.last
  assert(concurrent.surface.action_accepted(own_bid), 'Matching own ACK did not clear the field')
  assert(GameRoomCashAuction::Rules.bid!(concurrent.state, 0, 500, now: 102, revision: 2), 'Fixture refused the own bid')
  concurrent.refresh
  assert_equal('', concurrent.input.text)
  assert_equal(1, concurrent.surface.fields.length, 'Leading bidder still had a Pass button')
  assert_equal([:game, 0], concurrent.layout.focus_location, 'Own accepted bid lost field focus')
  concurrent.type('600')
  concurrent.press(13)
  assert_equal('600', concurrent.actions.last['answer'], 'Leader could not prepare an optional raise')
  stale_round = concurrent.actions.last
  assert(GameRoomCashAuction::Rules.finish_round!(concurrent.state), 'Fixture did not finish the first round')
  assert(GameRoomCashAuction::Rules.draw!(concurrent.state, category: 0, chest: false, now: 200), 'Fixture did not start the next round')
  concurrent.refresh
  assert_equal('cash-auction:native-cash-test:bid:2', concurrent.surface.state['question_id'])
  assert_equal('', concurrent.input.text, 'A new round reused the previous bid draft')
  concurrent.type('700')
  assert_equal(false, concurrent.surface.action_accepted(stale_round), 'Late earlier-round ACK cleared the new round')
  assert_equal('700', concurrent.input.text)
  concurrent.press(13)
  previous_game_receipt = concurrent.actions.last
  concurrent.state[:game_id] = 'native-cash-rematch'
  concurrent.refresh
  assert_equal('cash-auction:native-cash-rematch:bid:2', concurrent.surface.state['question_id'])
  assert_equal('', concurrent.input.text, 'A different game reused a bid from the same round number')
  concurrent.type('700')
  assert_equal(false, concurrent.surface.action_accepted(previous_game_receipt), 'An earlier-game ACK cleared an identical new-game draft')
  assert_equal('700', concurrent.input.text)
  assert_equal([], concurrent.replay.accepted_events)

  answer = CashAuctionNative::Fixture.new(phase: :answering)
  fixtures << answer
  question_text, answers = answer.surface.fields
  assert(question_text.is_a?(EditBox) && (question_text.flags & EditBox::Flags::ReadOnly) != 0, 'Question is not native read-only text')
  assert_equal(CashAuctionNative::QUESTION[:prompt], question_text.text)
  assert(answers.is_a?(ListBox), 'Answers are not a native list')
  assert_equal(['A. First', 'B. Second', 'C. Third', 'D. Fourth'], answers.options)
  answer.press(13)
  assert_equal([], answer.actions, 'Enter while reading the question answered it')
  answer.press(0x28)
  assert(answer.form.fields[answer.form.index].equal?(answers), 'Down did not enter ABCD answers')
  assert_equal(0, answers.index)
  answer.press(0x28)
  answer.press(13)
  assert_equal(1, answer.actions.length)
  assert_equal('1', answer.actions.last['answer'])
  assert_equal('question', answer.actions.last['kind'])
  assert_equal([], answer.replay.accepted_events)

  ['Bob', 'Observer'].each do |viewer|
    readonly = CashAuctionNative::Fixture.new(phase: :answering, viewer: viewer)
    fixtures << readonly
    before = Marshal.dump(readonly.state)
    assert_equal(CashAuctionNative::QUESTION[:prompt], readonly.surface.fields.first.text)
    assert_equal(['A. First', 'B. Second', 'C. Third', 'D. Fourth'], readonly.surface.fields[1].options)
    assert(readonly.surface.fields.none? { |field| field.is_a?(Button) }, 'Observer got a submit button')
    readonly.press(0x28)
    4.times do
      readonly.press(13)
      readonly.press(0x28)
    end
    assert_equal([], readonly.actions, 'A non-answering viewer submitted an ABCD answer')
    assert_equal(nil, readonly.surface.submission_action)
    assert_equal(before, Marshal.dump(readonly.state))
  end

  chest = CashAuctionNative::Fixture.new(phase: :opening_chests)
  fixtures << chest
  assert(chest.surface.fields.first.is_a?(Button), 'Chest action is not a native command button')
  chest.press(13)
  assert_equal({'kind'=>'command', 'action'=>'open_chest', 'round'=>1, 'remaining'=>2}, chest.actions.last)
  assert_equal([], chest.replay.accepted_events)
  observer = CashAuctionNative::Fixture.new(phase: :auction, viewer: 'Observer')
  fixtures << observer
  assert(observer.surface.fields.all? { |field| field.is_a?(EditBox) && (field.flags & EditBox::Flags::ReadOnly) != 0 }, 'Auction spectator received an editable control')
  observer.press(13)
  assert_equal([], observer.actions, 'Auction observer emitted a bid')

  puts 'Cash Auction native controls: typed bids/all-in, Tab Pass, rejection and ACK boundaries, protected editing, concurrent refresh, round drafts, ABCD, chests and readonly viewers passed without move writes.'
ensure
  fixtures.reverse_each(&:close)
  $activecontrols = []
end
