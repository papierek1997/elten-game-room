require_relative "../support/ui"
require_relative "../support/log"
class Program
  def self.server_app(**_options); end
end
require_relative "../../__app"
require_relative "../support/session_runner"
require_relative '../support/catalog_options'
require_relative '../support/contract_values'

$stdout.sync = true
tested = []
selected_ids = ENV['GAME_ROOM_TEST_GAME'] ? [ENV.fetch('GAME_ROOM_TEST_GAME')] : EltenGameRoom::GAME_REGISTRY.ids
selected_ids.each do |id|
  game = EltenGameRoom::GAME_REGISTRY.build(id)
  next unless game.supports_bots? && game.session_runner?
  # This fixture drives model actions, not the separate realtime engine.
  next if game.background_client?
  options = GameRoomTest::CatalogOptions.for_players(game, bots: true).merge('bot_delay' => 0)
  count = ([game.minimum_players, 2].max..game.maximum_players).find { |size| !game.validation_error(options, player_count: size) }
  h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], bots: count - 2, options: options)
  h.start
  next if game.controller_change_error(h.replay('Alice'), replacement: true)
  h.add_client('Watcher')
  assert(h.join('Watcher'), "#{id}: observer could not join")
  h.as('Watcher') { h.transports['Watcher'].set_observer(h.table, true, actor: 'Watcher') }
  h.as('Alice') { h.transports['Alice'].transfer_room_owner(h.table, 'Watcher') }
  # A confirmed membership departure, not a temporary lost update.
  h.as('Alice') { h.view('Alice').leave }
  master = runner_for(h, 'Watcher')
  human = runner_for(h, 'Bob')
  master.instance_variable_get(:@context_template).random_source = GameRoomRandom::SeededSource.new(137)
  tick = 0.0
  master.instance_variable_get(:@turn).instance_variable_set(:@clock, -> { tick })
  8.times do
    tick += 2
    # Paced games wait for the visible frame's presentation acknowledgement,
    # including when covered. This fixture has no physical screen; acknowledge
    # the same freshly read revision that a finished UI sequence would publish.
    if game.paced_event_presentation?
      [[master, 'Watcher'], [human, 'Bob']].each do |runner, viewer|
        shown = h.repositories.fetch(viewer).snapshot_for(h.session)
        runner.publish_view(session: shown.session, replay: game.replay(shown.session, shown.events, h.repositories.fetch(viewer)),
          busy: false, context: runner.send(:context))
      end
    end
    step(h, master, 'Watcher')
    step(h, human, 'Bob')
    # A human automatic action (for example accepting a Makao penalty) may
    # have just committed. Read its fresh revision before choosing a card.
    snapshot = h.repositories['Bob'].snapshot_for(h.session)
    current = game.replay(snapshot.session, snapshot.events, h.repositories['Bob'])
    break if current.finished?
    action = game.legal_actions(current, 'Bob', context: human.send(:context)).first
    if action
      h.as('Bob') do
        status, = human.submit(session: snapshot.session, replay: current, selection: action, actor: 'Bob')
        assert(status == :ok, "#{id}: remaining human action rejected: #{status}")
      end
    end
  end
  snapshot = h.repositories['Watcher'].snapshot_for(h.session)
  replay = game.replay(snapshot.session, snapshot.events, h.repositories['Watcher'])
  other = h.repositories['Bob'].snapshot_for(h.session)
  replacement = snapshot.session['__players'].first
  assert(GameRoomParticipants.bot?(replacement) && !snapshot.session['__players'].include?('Alice'), "#{id}: departed place was not physically replaced")
  rejected = snapshot.events.reject { |event| replay.accepted_events.include?(event) }
  assert(!snapshot.events.empty?, "#{id}: handover produced no moves")
  assert(rejected.empty?, "#{id}: automatic or bot event rejected: #{rejected.map { |event| event.to_h.slice('id', 'actor', 'action', 'value') }.inspect}")
  assert(snapshot.events == other.events, "#{id}: readers diverged")
  other_replay = game.replay(other.session, other.events, h.repositories['Bob'])
  assert(GameRoomTest::ContractValues.canonical(replay.state) == GameRoomTest::ContractValues.canonical(other_replay.state), "#{id}: replay diverged")
  assert(snapshot.events.any? { |e| e['actor'] == replacement }, "#{id}: new named bot never played in the first place")
  tested << id
  master.close
  human.close
  puts "#{id}: observer master, departed first seat, #{snapshot.events.size} accepted events"
end
assert(ENV['GAME_ROOM_TEST_GAME'] ? tested == selected_ids : tested.size >= 20, 'Insufficient handover coverage')
puts "Handover game contracts: #{tested.size} games OK"
