require_relative "../support/sequence_random"

require_relative "../support/native_room_harness"
require_relative "../support/ui"
require_relative "../support/log"
require_relative "../../lib/game_surfaces"
require_relative "../../lib/game_screen"
require_relative "../../games/categories"

module EltenAPI::Tasks
  class Cancelled < StandardError; end unless const_defined?(:Cancelled)
  def self.run(**_options)
    token = Object.new
    def token.raise_if_cancelled!; end
    yield nil, token
  end
end

def drain_wakeups(sync)
  20.times { return if sync.next_event.nil? }
  raise "wakeups did not settle"
end

def recovery_screen(h, user, context: nil, clock: [100.0])
  sync = GameRoomSync::Controller.new(transport: h.transports[user],
    table_id: h.table["__id"], session_id: h.session["__id"], clock: -> { clock[0] })
  drain_wakeups(sync)
  screen = GameScreen.allocate
  { repository: h.repositories[user], game: h.game || GameRoomGames::Base.new, game_services: {}, session: h.session,
    chat_sends: GameRoomUI::ChatSendBuffer.new,
    table: h.table, table_owner: h.users.first, synchronizer: sync,
    bot_turn_controller: h.repositories[user].bot_turn_controller(h.table["__id"]),
    room_snapshot_provider: -> {
      data = h.transports[user].room_snapshot(h.table)
      data && LobbyRepository::TableSnapshot.new(**data)
    }
  }.each { |key, value| screen.instance_variable_set("@#{key}", value) }
  screen.define_singleton_method(:alert) { |_text| nil }
  screen.define_singleton_method(:action_context) { context } if context
  screen.define_singleton_method(:game_recipients) { [] }
  [screen, sync]
end

failures = []
check = lambda do |name, &block|
  block.call
  puts "PASS: #{name}"
rescue StandardError => error
  failures << name
  puts "FAIL: #{name}: #{error.class}: #{error.message}"
end

check.call("uncertain bot write is verified against the server, not stale metadata") do
  h = NativeRoomHarness.new(users: %w[Alice Bob], bots: 1)
  h.start
  repo, view = h.repositories["Alice"], h.view("Alice")
  base = repo.snapshot_for(h.session)
  stale = view.stack_state.dup
  # The actual host exposes a local snapshot here, not the broker's live state.
  view.define_singleton_method(:stack_state) { stale.dup }
  h.broker.automatic_delivery = false
  actor = h.transports["Alice"].room_snapshot(h.table)[:bots].first
  command = GameRoomGames::EventCommand.new(action: "tick", value: "saved")
  gate = GameRoomBots::TurnController.new
  lease = gate.acquire(session_id: h.session["__id"], actor: actor, revision: repo.events_revision(base.events))
  gate.submitting(lease, events: [command])
  view.fail_next_push = :after
  begin
    h.as("Alice") { repo.append_events(session: h.session, sequence: 1, events: [command], actor: actor) }
  rescue EltenAPI::LiveSessions::TimeoutError
    gate.submission_failed(lease)
  end
  reads = view.calls[:read]
  verified = repo.snapshot_for(h.session, force_events: true)
  assert(view.calls[:read] == reads + 1, "forced verification made no real read")
  assert(verified.events.length == 1, "a persisted move was missing from verification")
  result = gate.observe(session_id: h.session["__id"], events: verified.events,
    confirmed_event_ids: repo.confirmed_event_ids(h.session), verified: true)
  assert(result == :confirmed, "the gate treated a persisted move as #{result}")
  assert(view.calls[:read] == reads + 1, "confirmation repeated the verification read")
  reads = view.calls[:read]
  repo.snapshot_for(h.session)
  repo.event_revision(h.session)
  repo.confirmed_event_ids(h.session)
  assert(view.calls[:read] == reads, "ordinary cached notifications started polling")
end

[:before, :after, :cancel].each do |fault|
  check.call("Categories automatic reveal recovers after #{fault}-commit failure") do
    game = GameRoomGames::Categories.new
    h = NativeRoomHarness.new(game: game, users: %w[Alice Bob])
    h.start
    contexts = h.users.to_h do |user|
      [user, GameRoomGames::ActionContext.new(session_id: h.session["__id"], table_id: h.table["__id"],
        hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
        random_source: GameRoomRandom::SequenceSource.new([1]), now: 1_000)]
    end
    h.submit("Alice", context: contexts["Alice"])
    answers = h.replay("Bob").state[:round_categories].to_h { |category| [category, "Example"] }
    h.submit("Bob", { "kind" => "answer_sheet", "action" => "submit", "answers" => answers }, context: contexts["Bob"])
    h.submit("Alice", context: contexts["Alice"])
    replay = h.replay("Bob")
    clock = [100.0]
    screen, sync = recovery_screen(h, "Bob", context: contexts["Bob"], clock: clock)
    view = h.view("Bob")
    stale = view.stack_state.dup
    view.define_singleton_method(:stack_state) { stale.dup }
    h.broker.automatic_delivery = false
    if fault == :cancel
      screen.define_singleton_method(:network_task) { |_title, **_options| nil }
    else
      view.fail_next_push = fault
    end
    h.as("Bob") do
      assert(!screen.send(:perform_automatic_action, replay), "uncertain write was reported as success")
      screen.singleton_class.remove_method(:network_task) if fault == :cancel
      assert(sync.next_reconcile_at.finite?, "failed automatic write did not schedule recovery")
      pushes = view.calls[:push]
      screen.send(:perform_automatic_action, replay)
      assert(view.calls[:push] == pushes, "uncertain action was blindly repeated")
      # A chat/room-only refresh cannot acknowledge the outstanding game repair.
      sync.synchronize(complete: false) { h.transports["Bob"].room_snapshot(h.table) }
      assert(sync.next_reconcile_at.finite?, "room refresh swallowed the recovery")
      clock[0] = 200.0
      assert(sync.next_event.kind == :recovery, "no recovery wakeup")
      result = sync.synchronize { screen.send(:recover_game_update, h.repositories["Bob"].events_revision(h.events("Bob"))) }
      assert(result[3] == :refresh, "recovery did not wake the automatic-action loop")
      fresh = h.replay("Bob")
      screen.send(:perform_automatic_action, fresh)
      h.broker.deliver
      assert(h.replay("Alice").state[:reveals].length == 1, "reveal never reached the judge")
      assert(view.calls[:push] == pushes + (fault == :after ? 0 : 1), "already persisted reveal was sent again")
      h.submit("Alice", context: contexts["Alice"])
      h.broker.deliver
      assert(h.replay("Bob").state[:phase] == :review, "round did not reach judging")
    end
  end
end

check.call("a failed new-game switch keeps its target until recovery succeeds") do
  h = NativeRoomHarness.new(users: %w[Alice Bob])
  h.start
  old = h.session
  clock = [100.0]
  screen, sync = recovery_screen(h, "Bob", clock: clock)
  h.start
  newest = h.session
  h.broker.automatic_delivery = false
  h.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: "new game")])
  event = sync.next_event
  assert(event.kind == :game_started, "missing new-game notification")
  screen.instance_variable_set(:@new_session_id, event.session_id)
  h.view("Bob").fail_next_read = EltenAPI::LiveSessions::TimeoutError.new("switch failed")
  screen.send(:switch_to_new_session)
  assert(screen.instance_variable_get(:@new_session_id) == newest["__id"], "pending target was lost")
  assert(sync.next_reconcile_at.finite?, "switch failure did not schedule a retry")
  layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new)
  layout.session_id = old['__id']
  layout.chat.set_text('hello while switching')
  screen.instance_variable_set(:@layout, layout)
  screen.send(:queue_chat_submission, layout.chat, layout.chat.text, session_id: old['__id'])
  screen.instance_variable_set(:@send_chat, ->(*_args, **_options) { raise 'Chat migrated to a different game' })
  screen.send(:submit_chat)
  assert(layout.chat.text == 'hello while switching', 'Discarding a stale intention removed its unsent text')
  assert(sync.next_reconcile_at.finite?, "chat cancelled the pending game switch")
  begin
    sync.synchronize(complete: false) { h.repositories["Bob"].snapshot_for(old) }
    raise 'A retired game was incorrectly returned as a readable snapshot'
  rescue GameRoomNetworkErrors::GamePaused
    assert(screen.instance_variable_get(:@new_session_id) == newest['__id'], 'Retired read lost the pending replacement')
  end
  clock[0] = 200.0
  event = sync.next_event
  if event.kind == :table_changed
    sync.synchronize(complete: false) { h.transports["Bob"].room_snapshot(h.table) }
    event = sync.next_event
  end
  assert(event.kind == :recovery, "room update cancelled the pending switch")
  result = sync.synchronize { screen.send(:recover_game_update, [0, 0]) }
  assert(result[3..4] == [:new_session, newest["__id"]], "recovery failed to select the new game")
  screen.send(:switch_to_new_session)
  assert(screen.instance_variable_get(:@session)["__id"] == newest["__id"], "screen stayed in the old game")
  assert(sync.session_id == newest["__id"] && screen.instance_variable_get(:@new_session_id).nil?, "switch was not acknowledged")
end

check.call("malformed participant packet cannot block later moves") do
  h = NativeRoomHarness.new(users: %w[Alice Bob])
  h.start
  h.broker.automatic_delivery = false
  bad = { "version" => 2, "kind" => "game_started", "actor" => "Bob", "data" => { "players" => "not an array" } }
  h.view("Bob").stack_push(bad, message_id: SecureRandom.uuid)
  h.write("Alice", [GameRoomGames::EventCommand.new(action: "tick", value: "after bad packet")])
  h.broker.deliver(duplicate: true)
  h.assert_converged("invalid packet skipped", expected_count: 1)
end

raise "Synchronization regressions: #{failures.join('; ')}" unless failures.empty?
puts "Synchronization regression tests passed"
