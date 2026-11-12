require_relative '../support/game_option_editor_native'
require_relative '../support/native_room_harness'
require_relative '../support/tournament_server_plan_table'
require_relative '../../lib/tournaments/ordinary_match_service'
require 'tmpdir'

module FixedTournamentSettingsNative
  T = GameRoomTournaments

  # Only task orchestration and unrelated telemetry are outside this fixture.
  # Native forms, the ordinary room writer/projection and binding service run.
  class Program < NativeOptionTest::Program
    def self.statistics_service; nil; end
    def run_network_task(_title, **_options, &operation); operation.call; end
  end

  class Menu
    attr_reader :items
    def initialize; @items = []; end
    def option(label, *_values, &block); @items << [label, block]; end
  end

  class Driver < NativeOptionTest::Driver
    def initialize(program, game, &operation)
      @program, @game, @raw_keys, @frames = program, game, [], 0
      NativeOptionUI.driver = self
      EltenAPI::KeyboardState.reset
      @fiber = Fiber.new(&operation)
      @form = @fiber.resume
      @fields = @form.fields.dup if @fiber.alive?
      NativeOptionTest.assert(@fiber.alive? && @form.instance_of?(GameRoomUI::Form),
        'Ordinary room did not open the native option editor')
    end
  end

  module_function

  def idle_input
    driver = NativeOptionTest::Driver.allocate
    driver.instance_variable_set(:@raw_keys, [])
    driver.instance_variable_set(:@frames, 0)
    NativeOptionUI.driver = driver
  end

  def waiting(h, lobby, table, services = {})
    program = Program.new
    program.instance_variable_set(:@lobby, lobby)
    program.instance_variable_set(:@games, h.repositories.fetch('Alice'))
    program.instance_variable_set(:@transport, h.transports.fetch('Alice'))
    program.instance_variable_set(:@table_activity,
      TableActivityRepository.new(server_tables: Object.new, transport: h.transports.fetch('Alice')))
    program.instance_variable_set(:@table_layouts, {})
    program.instance_variable_set(:@ordinary_tournament_services, services)
    state = program.send(:load_room_state, table, title: 'Read waiting room', force: true)
    assert(state.waiting? && !state.active? && state.session.nil?, 'Fixture is not an unstarted room')
    sync = GameRoomSync::Controller.new(transport: h.transports.fetch('Alice'), table_id: table.fetch('__id'))
    buffer = GameRoomUI::ChatSendBuffer.new
    idle_input
    layout = program.send(:present_table_screen, state, nil, table.fetch('__id'), nil, sync, buffer) {}
    context = -> { {table_id: table.fetch('__id'), session_id: nil, actor: 'Alice',
      membership: h.transports.fetch('Alice').membership_token(table.fetch('__id'))} }
    selection = program.send(:bind_waiting_table_screen, state, table, layout, sync,
      GameRoomHistory::Navigator.new, buffer, context)
    {program: program, state: state, layout: layout, selection: selection,
      sync: sync, buffer: buffer, context: context}
  end

  def menu(layout)
    Menu.new.tap { |value| layout.form.context(value, false) }
  end

  def native_record_count(h, table)
    h.broker.cores.fetch(table.fetch('__live_session_id')).entries.length
  end
end

F = FixedTournamentSettingsNative
$game_room_test_user = 'Alice'
NativeOptionTest.language = 'en'
NativeOptionTest.native_method(ListBox, :initialize, 'src/ui/controls/list_box.rb')
NativeOptionTest.native_method(Form, :context, 'src/ui/form.rb')
game = GameRoomGames::CATALOG.build('domino')
users = %w[Alice Bob Carol Dave]
options = game.normalize_options(game.default_options.merge('teams' => true, 'team_count' => '2', 'score_limit' => 1))
h = NativeRoomHarness.new(game: game, users: users, options: options)
programs = users.to_h { |user| [user, ProgramDouble.new(h.broker.endpoint(user))] }
lobbies = users.to_h do |user|
  [user, LobbyRepository.new(programs.fetch(user), transport: h.transports.fetch(user), server_tables: Object.new)]
end
ordinary = F.waiting(h, lobbies.fetch('Alice'), h.table)
ordinary_menu = F.menu(ordinary.fetch(:layout))
assert(ordinary_menu.items.any? { |label, _| label == 'Choose teams' }, 'Ordinary doubles lost team editing')
edit = ordinary_menu.items.find { |label, _| label == 'Change settings for the next game' }
assert(edit, 'Ordinary room lost its settings editor')
edit.last.call
assert_equal(:edit_options, ordinary.fetch(:selection).fetch(:action))
driver = F::Driver.new(ordinary.fetch(:program), game) do
  ordinary.fetch(:program).send(:execute_waiting_table_action, ordinary.fetch(:selection),
    ordinary.fetch(:state), h.table, ordinary.fetch(:layout), ordinary.fetch(:buffer),
    ordinary.fetch(:context), ordinary.fetch(:sync))
end
driver.number('score_limit', 2)
save = driver.form.fields.find { |field| field.is_a?(Button) && field.label == 'Save changes' }
assert(save, 'The native editor has no Save changes')
driver.focus(save)
driver.press([13])
driver.finished
ordinary_room = lobbies.fetch('Alice').snapshot_for(h.table, force: true)
assert_equal(2, JSON.parse(ordinary_room.table.fetch('game_options')).fetch('score_limit'),
  'Ordinary native editor no longer persists legal options')
assert(h.transports.fetch('Alice').change_game_options(table: ordinary_room.table,
  options: JSON.generate(JSON.parse(ordinary_room.table.fetch('game_options')).merge('score_limit' => 3)),
  expected_options: ordinary_room.table.fetch('game_options'), expected_session_id: 0),
  'Ordinary lower writer was blocked')

# Retained menu callbacks must resolve current providers, not their old list.
# These are two genuine fixture rooms, not a claim that a room changes identity.
provider_room, provider_session = ordinary_room, nil
stale_calls = []
F.idle_input
stale_layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new,
  history_items: [], phase: :waiting, own_table: true)
GameRoomParticipantMenu.bind(stale_layout,
  available: -> { [:edit_options, :edit_teams, :rules] }, game: game,
  room: -> { provider_room }, control: -> { {session: provider_session} },
  read_options: -> { stale_calls << :read_options }) { |action, _| stale_calls << action }
old_menu = F.menu(stale_layout)
old_edits = old_menu.items.select { |label, _| ['Change settings for the next game', 'Choose teams'].include?(label) }
assert_equal(2, old_edits.length)
ordinary.fetch(:layout).begin_bindings
h.as('Alice') { lobbies.fetch('Alice').close_table(h.table) }

Dir.mktmpdir('fixed-tournament-settings-') do |directory|
  docs = TournamentServerPlanTableSupport::Table.new(user: -> { 'Alice' })
  reference = {'author' => 'alice', 'publication_key' => 'fixture'}
  match = {'match_id' => 'd' * 64, 'leg' => 1, 'number' => 1,
    'players' => users.map(&:downcase), 'unit_ids' => %w[red blue]}
  candidate = {'schedule_id' => 'a' * 64, 'publication_digest' => 'b' * 64,
    'roster_generation' => 'c' * 64, 'game_id' => game.id, 'publication_ref' => reference,
    'format' => 'round_robin', 'players_per_match' => 4, 'game_options' => options,
    'roster' => users.map(&:downcase), 'team_template' => [0, 1, 0, 1],
    'membership' => {'version' => 1, 'kind' => 'fixed-teams', 'units' => [
      {'unit_id' => 'red', 'accounts' => %w[alice bob]},
      {'unit_id' => 'blue', 'accounts' => %w[carol dave]}]}, 'matches' => [match]}
  services = users.to_h do |user|
    journal = F::T::OperationJournal.new(directory: File.join(directory, user),
      owner: user.downcase, backend_identity: 'fixed-settings-native')
    [user, F::T::OrdinaryMatchService.new(program: programs.fetch(user), registry: GameRoomGames::CATALOG,
      lobby: lobbies.fetch(user), games: h.repositories.fetch(user), transport: h.transports.fetch(user),
      table: docs.for_user(user), journal: journal,
      source: -> { {'candidate' => candidate, 'tournament_id' => 5} }, user: -> { user })]
  end
  table = nil
  begin
    table = h.as('Alice') { services.fetch('Alice').open_match(match_id: match.fetch('match_id'), leg: 1) }
    users.drop(1).each do |user|
      h.as(user) { services.fetch(user).open_match(match_id: match.fetch('match_id'), leg: 1) }
    end
    bound = F.waiting(h, lobbies.fetch('Alice'), table, JSON.generate(reference) => services.fetch('Alice'))
    current = bound.fetch(:state).room
    before_options = current.table.fetch('game_options').dup
    parameters = services.fetch('Alice').start_parameters(current.table,
      players: current.game_participants, options: game.options_from_json(before_options))
    assert(parameters.fetch(:requested_session_id).positive?, 'Original fixed binding is not startable')
    labels = F.menu(bound.fetch(:layout)).items.map(&:first)
    assert(!labels.include?('Change settings for the next game') && !labels.include?('Choose teams'),
      'Waiting fixed tournament room exposes settings/team mutation')
    assert(labels.include?('Game rules') && labels.include?('Read the table variant and settings'),
      'Fixed tournament filtering removed read-only inspection')
    tips = GameRoomContextHelp.field_tips(bound.fetch(:layout).users)
    assert(tips.none? { |tip| tip.include?('Ctrl+X') }, 'Fixed tournament help still advertises settings mutation')
    provider_room = current
    old_edits.each { |_, callback| callback.call }
    assert(stale_calls.empty?, 'Old ordinary menu callback dispatched into a fixed tournament context')
    # Even a session-only marker must invalidate retained callbacks.
    provider_room = ordinary_room
    provider_session = {'__tournament_match' => {}}
    old_edits.each { |_, callback| callback.call }
    assert(stale_calls.empty?, 'Session-only tournament marker bypassed the common menu guard')

    records = F.native_record_count(h, table)
    no_ui = Object.new
    no_ui.define_singleton_method(:tick) { |_| raise 'Fixed tournament direct edit opened a native form' }
    NativeOptionUI.driver = no_ui
    program = bound.fetch(:program)
    assert_equal(false, program.send(:change_table_game_options, current.table))
    assert_equal(false, program.send(:change_table_teams, current.table))
    changed = game.options_from_json(before_options).merge('score_limit' => 2)
    assert_equal(false, h.transports.fetch('Alice').change_game_options(table: current.table,
      options: JSON.generate(changed), expected_options: before_options, expected_session_id: 0))
    assert_equal(false, h.transports.fetch('Alice').change_game_options(table: current.table,
      options: before_options, expected_options: before_options, expected_session_id: 0),
      'An unchanged payload bypassed the fixed tournament writer guard')
    assert_equal(records, F.native_record_count(h, table), 'Fixed tournament refusal appended native records')
    fresh = lobbies.fetch('Alice').snapshot_for(table, force: true)
    assert_equal(before_options, fresh.table.fetch('game_options'), 'Fixed tournament options changed despite refusal')
    assert_equal(parameters, services.fetch('Alice').start_parameters(fresh.table,
      players: fresh.game_participants, options: game.options_from_json(before_options)))
    started = program.send(:start_new_game, fresh.table)
    assert_equal(parameters.fetch(:requested_session_id), started.fetch('__id'),
      'The unchanged fixed tournament can no longer start normally')
    assert_equal(1, h.transports.fetch('Alice').game_sessions(table, force: true).length)
  ensure
    bound&.fetch(:layout)&.begin_bindings
    stale_layout.begin_bindings
    services.each_value(&:close)
    h.as('Alice') { lobbies.fetch('Alice').close_table(table) } if table
  end
end
puts 'PASS fixed tournament settings: native menu/help, stale callbacks, direct editors, lower writer, ordinary doubles and unchanged bound Start'
