require_relative '../support/tournament_native'
require File.join(EltenTestHost.root, 'src/ui/controls/grid_box')
Object.send(:remove_const, :GridBox) if Object.const_defined?(:GridBox, false)
Object.const_set(:GridBox, EltenAPI::Controls.const_get(:GridBox))
require_relative '../support/tournament_individual_execution'
require_relative '../support/tournament_declared_team_execution'
require_relative '../../lib/tournaments/local_realtime_individual_execution'
require_relative '../../lib/tournaments/local_realtime_game_dialog'
include TournamentIndividualExecutionSupport
include TournamentDeclaredTeamExecutionSupport

class RealtimeUIAudio
  attr_reader :closed
  def load; end
  def reset; end
  def update(*_arguments, **_options); end
  def suspend; end
  def silence; end
  def tick; end
  def ready(*_arguments); end
  def holder(*_arguments); end
  def announce_set(*_arguments); end
  def close; @closed = true; end
end
class RealtimeUIChannel
  attr_accessor :required_members
  attr_reader :epoch, :closed
  def initialize; @epoch = nil; end
  def tick; end
  def connected?; false; end
  def configure_p2p(_options); end
  def enable_events(*_arguments, **_options); end
  def take_events; []; end
  def take_packets; {}; end
  def send(*_arguments); false; end
  def send_event(*_arguments); false; end
  def reconnect(**_options); end
  def close; @closed = true; end
end
language = ARGV.include?('--pl') ? 'pl' : 'en'
GameRoomLocalization.boot(settings: {'interface_language' => language, 'known_languages' => [language]})
translate = ->(value) { GameRoomContent.utf8(GameRoomLocalization.translate(value)) }
audio_ball = ARGV.include?('--audio-ball')
teams = ARGV.include?('--teams')
raise 'This UI scenario has no Audio Ball team mode' if teams && audio_ball
uncertain_start = audio_ball && ARGV.include?('--uncertain-start')
with_fixture(game: audio_ball ? 'audio_ball' : 'axel_pong', names: teams ? %w[Alice Bob Carol Dave] : %w[Alice Bob], rematch: false,
  players_per_match: teams ? 4 : nil, game_options: audio_ball ? {} : {'target' => 7, 'team_size' => teams ? 2 : 0}) do |fixture|
  klass = T::LocalRealtimeIndividualExecution
  record = teams ? start_declared_team_match(fixture) : start_individual_match(fixture, execution_class: klass)
  owner = record['evidence']['plan']['matches'].first['players'].first['username']
  execute = lambda do |&block|
    teams ? with_declared_team_execution(fixture, record, owner, &block) :
      with_individual_execution(fixture, record, owner, execution_class: klass, &block)
  end
  execute.call do |execution, authority|
    if audio_ball && !uncertain_start
      status = execution.local_game(action: :local_game_status)[:status]
      initial = execution.local_game(action: :local_game_move, operation_id: 'ui-audio-start',
        revision: status['revision'], move_selection: status['actions'].first)
      assert_equal(:confirmed, initial[:state])
    end
    context = authority.instance_variable_get(:@entry)
    program = context.instance_variable_get(:@program)
    program.define_singleton_method(:communication) { nil }
    controller = Object.new
    calls = []
    lose_start = uncertain_start
    controller.define_singleton_method(:perform) do |action:, selectors:, **options|
      calls << [action, Thread.current]
      result = execution.local_game(action: action, **options)
      if lose_start && action == :local_game_move
        assert_equal(:confirmed, result[:state], 'Simulated lost reply must follow an actual successful write')
        lose_start = false
        result = {state: :uncertain}
      end
      {action == :local_realtime_view ? :realtime_surface : :local_game => result}
    end
    view = execution.local_game(action: :local_realtime_view)
    header = nil # Native custom fields expose no EditBox header.
    count = audio_ball ? 1 : 0
    baseline = 0
    shortcut_commands = []
    audio, channel = RealtimeUIAudio.new, RealtimeUIChannel.new
    dialog = T::MatchEntryScreen::RealtimeGame.new(program: program, controller: controller, selectors: {},
      result: view, context: context, lease: context.capture,
      services: {audio: audio, channel_factory: ->(**_args) { channel }})
    driver = TournamentNativeDriver.new
    if uncertain_start
      driver.step(header) do |form|
        dialog.send(:advance_entry) # Initial subscription reconciliation.
        wait_background_work(dialog.instance_variable_get(:@work), timeout: 30)
        dialog.send(:advance_entry) # Existing automatic start, exactly once.
        wait_background_work(dialog.instance_variable_get(:@work), timeout: 30)
        dialog.send(:advance_entry)
        assert_equal(:uncertain, dialog.instance_variable_get(:@last_result)[:state])
        assert(dialog.instance_variable_get(:@intent), 'Uncertain initial randomization must retain its original operation')
        before = calls.size
        5.times { dialog.send(:advance_entry) }
        assert_equal(before, calls.size, 'An uncertain initial write must never be retried automatically')
        form.fields.grep(Button).find { |field| field.label == translate.call('Check status') }.press
        wait_background_work(dialog.instance_variable_get(:@work), timeout: 30)
        dialog.send(:advance_entry)
        if dialog.instance_variable_get(:@pending)
          wait_background_work(dialog.instance_variable_get(:@work), timeout: 30)
          dialog.send(:advance_entry)
        end
        assert_equal(nil, dialog.instance_variable_get(:@intent))
        assert_equal(1, calls.count { |call| call.first == :local_game_move })
        assert_equal(1, dialog.instance_variable_get(:@status)['event_count'])
        baseline = calls.size
      end
    end
    driver.step(header) do |form|
      assert(form.is_a?(GameRoomUI::Form), 'Realtime match must use the native guarded form')
      commands = shortcut_commands
      surface = dialog.instance_variable_get(:@surface)
      original_command = surface.method(:handle_command)
      surface.define_singleton_method(:handle_command) do |command, payload = {}|
        commands << [command, Thread.current]
        original_command.call(command, payload)
      end
      # Current native handlers use press-time state, not the later Boolean
      # event arguments. Exercise the same snapshot boundary as real input.
      press = lambda do |key, shift: false, control: false|
        EltenAPI::KeyboardState.reset
        raw = "\0" * 256
        code = EltenAPI::KeyboardScheme.key_code(key) || form.__send__(:keyboard_code, key).first
        raw.setbyte(code, 0x80)
        raw.setbyte(0x10, 0x80) if shift
        raw.setbyte(EltenAPI::KeyboardScheme.key_code(EltenAPI::KeyboardScheme.main_modifier), 0x80) if control
        EltenAPI::KeyboardState.update(raw_state: raw, events: [[code, true, raw]])
        $input_frame_serial = $input_frame_serial.to_i + 1
        $keyboard_state_frame_serial = $input_frame_serial
        $keyboard_state_frame_thread = Thread.current
        expected = (shift ? [:shift] : []) + (control ? [:control] : [])
        assert_equal(expected.sort, GameRoomUI.modifiers_when_pressed(form, key), 'Native shortcut press snapshot was not installed')
        form.trigger(("key_" + key.to_s).to_sym, shift, control, false)
      ensure
        EltenAPI::KeyboardState.clear_current_frame
      end
      press.call(:s, shift: audio_ball)
      press.call(:w)
      press.call(:w, control: true)
      assert_equal(['scores', 'hurry'], commands.map(&:first))
      assert(commands.all? { |command| command.last == Thread.current }, 'Client shortcuts must remain on active UI')
      button = form.fields.grep(Button).find { |field| field.label == translate.call('Check status') }
      assert(button, 'Explicit status refresh must be available')
      button.press
      wait_background_work(dialog.instance_variable_get(:@work), timeout: 30)
      dialog.send(:advance_entry)
      assert_equal(baseline + 2, calls.size)
      assert(calls.all? { |call| call.last != Thread.current }, 'Native game reads must use finite Tasks work')
      assert_equal(count, dialog.instance_variable_get(:@status)['event_count'])
      identity = view[:effect].fetch(:change_identity)
      Thread.new { 5.times { T::LocalGameEvents.publish(identity) } }.join
      dialog.send(:advance_entry)
      wait_background_work(dialog.instance_variable_get(:@work), timeout: 30)
      dialog.send(:advance_entry)
      assert_equal(baseline + 4, calls.size, 'Coalesced commit signals must schedule one finite refresh')
      T::LocalGameEvents.publish('a-different-local-store')
      5.times { dialog.send(:advance_entry) }
      assert_equal(baseline + 4, calls.size, 'Idle UI and unrelated stores must not trigger I/O')
      button.press
      Thread.new { T::LocalGameEvents.publish(identity) }.join
      wait_background_work(dialog.instance_variable_get(:@work), timeout: 30)
      dialog.send(:advance_entry)
      wait_background_work(dialog.instance_variable_get(:@work), timeout: 30)
      dialog.send(:advance_entry)
      assert_equal(baseline + 8, calls.size, 'A signal arriving during pending work must survive until another validated read')
      5.times { dialog.send(:advance_entry) }
      assert_equal(baseline + 8, calls.size, 'Pending-work recovery must return to idle without polling')
    end
    driver.step(header, audio_ball ? [16, 83] : [83])
    driver.step(header) do |_form|
      assert_equal(['scores', 'hurry', 'scores'], shortcut_commands.map(&:first),
        'Native keyboard dispatch must reach the same game shortcut handler')
    end
    driver.step(header, [27])
    dialog.run
    driver.finish
    assert(audio.closed && channel.closed, 'Back must close the actual client audio and channel')
    assert(dialog.instance_variable_get(:@work).closed?, 'Modal must close its finite work resource')
    assert_equal(baseline + 8, calls.size, 'No periodic server or file polling is allowed')
    T::LocalGameEvents.publish(view[:effect].fetch(:change_identity))
    assert(!dialog.instance_variable_get(:@changes).take, 'Closing must discard later commit signals')
    status = execution.local_game(action: :local_game_status)[:status]
    assert_equal(count, status['event_count'])
    assert(!status['finished'], 'Leaving a realtime view must not invent a result or forfeit')
    original_name = Session.method(:name) if defined?(Session) && Session.respond_to?(:name)
    begin
      Session.define_singleton_method(:name) { 'OtherAccount' } if defined?(Session)
      guarded = T::MatchEntryScreen::RealtimeGame.new(program: program, controller: controller, selectors: {},
        result: view, context: context, lease: context.capture, services: {audio: RealtimeUIAudio.new})
      guard_driver = TournamentNativeDriver.new
      guard_driver.step(header) do |_form|
        assert(guarded.instance_variable_get(:@blocked), 'A different signed-in account must not open a peer channel')
        assert_equal(nil, guarded.instance_variable_get(:@bridge))
        assert_equal(nil, guarded.instance_variable_get(:@work))
        assert_equal(translate.call('The realtime game view must use your signed-in account.'),
          guarded.instance_variable_get(:@status_field).text)
      end
      guard_driver.step(header, [27])
      guarded.run
      guard_driver.finish
      assert_equal(baseline + 8, calls.size, 'The account guard must not request a write or a background read')
    ensure
      Session.define_singleton_method(:name) { original_name.call } if original_name
    end
  end
end
puts 'PASS native realtime modal: real guarded Form, explicit finite Tasks refresh, no polling/false result, Back closes client/channel/audio and work'
