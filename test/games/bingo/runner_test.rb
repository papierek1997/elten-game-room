require_relative "../../support/session_runner"
require_relative "../../../games/bingo"

class BingoRunnerClock
  attr_accessor :value
  def initialize(value); @value = value; end
  def now(_session); value; end
end

%w[30 75 80 90].each do |variant|
  game = GameRoomGames::Bingo.new
  h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], options: game.normalize_options("variant" => variant))
  h.start
  host, guest = runner_for(h), runner_for(h, "Bob")
  begin
    clock = BingoRunnerClock.new(Time.now.to_i)
    host.instance_variable_set(:@clock, clock)
    step(h, host)
    assert(h.events("Alice").map { |event| event['action'] } == ['start'], "#{variant}: missing native start")
    current = h.replay("Alice")
    clock.value = current.state[:next_at] - 1
    step(h, host)
    assert(h.events("Alice").size == 1, "#{variant}: caller ignored the deadline")
    clock.value += 1
    step(h, guest, "Bob")
    assert(h.events("Bob").size == 1, "#{variant}: guest became a second caller")
    step(h, host)
    events = h.events("Alice")
    assert(events.map { |event| event['action'] } == %w[start draw], "#{variant}: covered runner did not call a ball")
    assert(events.all? { |event| event['__server_random'] }, "#{variant}: caller omitted server randomness")
    assert(h.replay("Alice").accepted_events.size == events.size, "#{variant}: executor wrote rejected calls")
    h.assert_converged("bingo/#{variant} covered call")
  ensure
    host.close
    guest.close
  end
end
puts "Bingo active executor: four variants, native start/draw ACK, covered deadline, guest isolation and converged replay passed"
