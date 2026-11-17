require_relative 'native_room_harness'
require_relative 'audio_ball_client'
require_relative '../../games/four_in_a_row'

# In-memory native-session broker and clocked UI peripherals. The production
# GameScreen#run, repository writes, replay, timers and clients are not replaced.
module BackgroundGameScreenSupport
  PROGRESS_TIMEOUT = 30.0
end

module EltenAPI::Tasks
  class Cancelled < StandardError; end unless const_defined?(:Cancelled)
  class CancellationToken
    def cancelled?; false; end
    def raise_if_cancelled!; end
    def cancel(*_args); end
  end
  def self.run(**options)
    options[:ui].update if options[:ui].respond_to?(:update)
    yield nil, options[:cancellation_token] || CancellationToken.new
  end
end

# Share the actual host timer type with realtime subclasses. Advance only
# ordinary maintenance timers with the fixture clock; realtime keeps native
# lifecycle/update and the match clock supplied by the client.
Object.send(:remove_const, :FormTimer)
FormTimer = EltenAPI::Controls::FormTimer
class FormTimer
  alias native_update update
  def update
    return native_update unless instance_of?(FormTimer)
    return if @monotonic_starttime == nil || @completed
    @fixture_due ||= $help_clock + @time
    return unless $help_clock >= @fixture_due
    @fixture_due = $help_clock + @time
    @completed = true unless @repeat
    @action.call
  end
end
class FakeControl
  def key_held?(_key); false; end
  def key_pressed?(_key); false; end
end
class Form
  class << self; attr_accessor :driver; end
  def wait
    @wait = true
    # The managed bot worker uses real pacing and performs real search. A
    # synthetic frame count is not a time budget for that asynchronous work.
    # Preserve both the normal delay and strategy; bound a stuck test by the
    # actual elapsed time instead of outrunning the worker with the UI clock.
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + BackgroundGameScreenSupport::PROGRESS_TIMEOUT
    while @wait
      $help_clock += 0.016
      $help_frames += 1
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "Game did not progress while help was open within #{BackgroundGameScreenSupport::PROGRESS_TIMEOUT.to_i} seconds (#{$help_frames} fixture frames)"
      end
      Form.driver.call(self)
      update
      Thread.pass # The real session worker, not a synchronous UI bot, must run.
    end
  end
  def update
    $activecontrols = [self]
    fields[index.to_i]&.update
    @timers.to_a.dup.each(&:update)
  end
  def resume; @wait = false; end
  def focus(*_args); fields[index.to_i]&.focus; end
  def keyboard_idle_frame?; true; end
end

def screen_fixture(game, bots: 0, **screen_options)
  $help_clock, $help_frames = 0.0, 0
  $game_room_test_user = 'Alice' # Host identity also exists on the managed worker.
  h = NativeRoomHarness.new(game: game, users: bots > 0 ? ['Alice'] : %w[Alice Bob], bots: bots)
  h.start
  sync = GameRoomSync::Controller.new(transport: h.transports['Alice'], table_id: h.table['__id'],
    session_id: h.session['__id'], clock: -> { $help_clock })
  screen = GameScreen.new(program: ProgramDouble.new(h.broker.endpoint('Alice')),
    repository: h.repositories['Alice'], game: game, session: h.session,
    table: h.table, table_owner: 'Alice', synchronizer: sync,
    game_services: {transport: h.transports['Alice']},
    **screen_options, room_snapshot_provider: -> {
      data = h.transports['Alice'].room_snapshot(h.table)
      data && LobbyRepository::TableSnapshot.new(**data)
    })
  screen.define_singleton_method(:alert) { |text| raise "Unexpected alert: #{text}" }
  screen.define_singleton_method(:monotonic_time) { $help_clock }
  [h, screen]
end

# Keep the real random recipe/write/replay path. A hidden human does not serve;
# these background-progress scenarios specifically need the bot to start.
def bot_serves_audio_ball(harness)
  values = Array.new(15, 1) + [2]
  assert(GameRoomServerRandomRendering.render({'kind' => 'first_server'}, values) == '1',
    'Fixture must let the bot serve first')
  harness.view('Alice').next_random_values = values
end
