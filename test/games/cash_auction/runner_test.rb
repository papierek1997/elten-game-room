require_relative '../../support/session_runner'
require_relative '../../../games/cash_auction'

class CashAuctionRunnerClock
  attr_accessor :value
  def initialize(value); @value = value; end
  def now(_session); value; end
  def server_now; value; end
end

original_now = Time.method(:now)
clock = CashAuctionRunnerClock.new(original_now.call.to_i)
Time.define_singleton_method(:now) { Time.at(clock.value) }
runners = []
begin
  game = GameRoomGames::CashAuction.new
  room = NativeRoomHarness.new(game: game, users: %w[Alice Bob], options: game.table_creation_options)
  room.start
  host, guest = %w[Alice Bob].map { |user| runner_for(room, user) }
  runners.concat([host, guest])
  runners.each { |runner| runner.instance_variable_set(:@clock, clock) }
  room.view('Alice').next_random_values = Array.new(16, 1)
  step(room, host)
  assert(room.replay('Alice').state[:phase] == :spinning, 'The ordinary executor did not spin the wheel')
  assert(room.events('Alice').first['__server_random'], 'The wheel omitted native server randomness')
  clock.value += 3
  step(room, guest, 'Bob')
  assert(room.events('Bob').length == 1, 'The guest became a second category caller')
  step(room, host)
  opening = room.replay('Alice')
  assert(opening.state[:phase] == :auction && !opening.state[:chest], 'The native ante did not open a question auction')
  stale_bob = room.replay('Bob')
  %w[Alice Bob].zip(%w[100 200], [opening, stale_bob], [host, guest]).each do |user, amount, replay, runner|
    selection = {'kind'=>'question', 'action'=>'submit', 'question_id'=>game.surface_spec(replay, user).id, 'answer'=>amount}
    room.as(user) do
      status, = runner.submit(session: room.session, replay: replay, selection: selection, actor: user)
      assert(status == :ok, 'The ordinary executor refused a concurrent bid from the same auction')
    end
  end
  room.assert_converged('concurrent auction bids', expected_count: 4)
  state = room.replay('Alice').state
  assert(state[:cash] == [890, 790] && state[:pot] == 320, 'Native ACK changed the bid ledger')
  clock.value = state[:auction_deadline] - 1
  step(room, host)
  assert(room.events('Alice').length == 4, 'The executor closed the auction early')
  clock.value += 1
  step(room, host)
  assert(room.replay('Alice').state[:phase] == :question_pending, 'The third call did not close the auction')
  room.view('Alice').next_random_values = Array.new(16, 2)
  step(room, host)
  answering = room.replay('Bob')
  assert(answering.state[:phase] == :answering, 'The executor did not request a separate question seed')
  assert(room.events('Alice').count { |event| event['__server_random'] } == 2, 'Question randomness was reused or drawn before the auction ended')
  selection = {'kind'=>'question', 'action'=>'submit', 'question_id'=>game.surface_spec(answering, 'Bob').id,
    'answer'=>answering.state[:question][:correct_index].to_s}
  room.as('Bob') do
    status, = guest.submit(session: room.session, replay: answering, selection: selection, actor: 'Bob')
    assert(status == :ok, 'The winner could not answer through the executor')
  end
  room.assert_converged('answered auction', expected_count: 7)
  assert(room.replay('Alice').state[:cash] == [890, 1110], 'Executor payout differs from cold native replay')
  assert(room.replay('Alice').accepted_events.length == room.events('Alice').length, 'The executor wrote a refused event')
  [false, true].each do |chest|
    clock.value = room.replay('Alice').state[:resume_at]
    value = (1..256).find { |candidate| (Random.new((('%02x' % (candidate - 1)) * 16).to_i(16)).rand(100) < 5) == chest }
    assert(value, 'No bounded native wheel seed for the all-in scenario')
    room.view('Alice').next_random_values = Array.new(16, value)
    before_count = room.events('Alice').length
    step(room, host)
    clock.value += 3
    step(room, host)
    actor, bidder, opponent, other = chest ? ['Bob', guest, 'Alice', host] : ['Alice', host, 'Bob', guest]
    current, stale = room.replay(actor), room.replay(opponent)
    assert(current.state[:chest] == chest, 'Native wheel did not select the requested auction')
    late = {'kind'=>'question', 'action'=>'submit', 'question_id'=>game.surface_spec(stale, opponent).id,
      'answer'=>stale.state[:cash][stale.players.index(opponent)].to_s}
    selection = {'kind'=>'question', 'action'=>'submit', 'question_id'=>game.surface_spec(current, actor).id, 'answer'=>'A'}
    room.as(actor) do
      status, = bidder.submit(session: room.session, replay: current, selection: selection, actor: actor)
      assert(status == :ok, 'Native all-in was refused')
    end
    room.assert_converged('immediate all-in', expected_count: before_count + 3)
    awarded = room.replay(actor)
    assert(awarded.state[:phase] == (chest ? :drawing : :question_pending), 'All-in waited for the third call')
    assert(room.events(actor).last['action'] == 'all_in', 'Native all-in lost its terminal identity')
    room.as(opponent) do
      assert_raises(GameRoomSessionRunner::StaleView) do
        other.submit(session: room.session, replay: stale, selection: late, actor: opponent)
      end
    end
    assert(room.events(actor).length == before_count + 3, 'A later bidder wrote after all-in')
    if chest
      assert(awarded.state[:chests][1] == 1, 'All-in did not award the chest immediately')
      assert(room.events(actor).count { |event| event['action'] == 'question' } == 2, 'Chest requested a question')
    else
      room.view('Alice').next_random_values = Array.new(16, 2)
      step(room, host)
      answering = room.replay(actor)
      assert(answering.state[:phase] == :answering, 'Question did not follow all-in at the same clock time')
      selection = {'kind'=>'question', 'action'=>'submit', 'question_id'=>game.surface_spec(answering, actor).id,
        'answer'=>answering.state[:question][:correct_index].to_s}
      room.as(actor) { assert(bidder.submit(session: room.session, replay: answering, selection: selection, actor: actor).first == :ok) }
      room.assert_converged('answered all-in', expected_count: before_count + 5)
    end
  end
  puts 'Cash Auction ordinary executors: native random wheel/question, no guest caller, concurrent stale-view bids, strict deadline, answer/payout and two-client cold replay convergence passed.'
  puts 'Cash Auction native all-in: immediate question/chest award, stale competing write refusal and same-clock question progression passed.'
ensure
  runners.each(&:close)
  Time.define_singleton_method(:now, original_now)
end
