require_relative "../support/host_source"
require_relative "../support/ui"
require "weakref"
module Log
  def self.debug(_message); end
  def self.warning(_message); end
end
require EltenTestHost.file("src/eapi/resources.rb")
require EltenTestHost.file("src/eapi/program.rb")
require EltenTestHost.file("src/eapi/quickactions.rb")
require EltenTestHost.file("src/eapi/notificationgroups.rb")
require_relative "../../lib/game_room_ui"

def assert(value, message)
  raise message unless value
end

BridgeManifest = Struct.new(:namespace_name)
BridgeNotice = Struct.new(:id, :cat, :app_uuid, :date, :update_time, :revoked, :payload, :alert, keyword_init: true)
UI_PATH = File.expand_path("../../lib/game_room_ui.rb", __dir__)
RECEIPT_PATH = File.expand_path("../../lib/invitation_receipts.rb", __dir__)
LEGACY_SOURCE = File.binread(File.expand_path("../fixtures/host_bridges_legacy.rb", __dir__))
UI_SOURCE = File.binread(UI_PATH)
RECEIPT_SOURCE = File.binread(RECEIPT_PATH)

def bridge_generation(name, legacy: false)
  # Native Runtime resource ownership and native RuntimeBackend namespace
  # disposal, with no manifest/disk/network setup.
  runtime = Programs::Runtime.allocate
  runtime.instance_variable_set(:@manifest, BridgeManifest.new(name))
  backend = Programs::Execution::RuntimeBackend.new(runtime)
  runtime.instance_variable_set(:@namespace, backend.namespace)
  runtime.instance_variable_set(:@execution, backend)
  space = backend.namespace
  if legacy
    # Keep genuine source locations so migration can identify only our bridge.
    hotkeys, receipts = LEGACY_SOURCE.split("module GameRoomInvitationReceipts", 2)
    backend.evaluate(hotkeys, UI_PATH)
    backend.evaluate("module GameRoomInvitationReceipts" + receipts, RECEIPT_PATH)
  else
    helper = File.expand_path("../../lib/host_bridge.rb", __dir__)
    backend.evaluate(File.binread(helper), helper)
    backend.evaluate(UI_SOURCE, UI_PATH)
    backend.evaluate(RECEIPT_SOURCE, RECEIPT_PATH)
  end
  program_source = <<~'RUBY'
    class BridgeProgram < ::Program
      def self.server_app_uuid; "test-bridge-app"; end
      def self.receive_invitation_receipt(value); (@receipts ||= []) << value.id; end
      def self.receipts; @receipts || []; end
    end
  RUBY
  Programs.with_runtime(runtime) { backend.evaluate(program_source, "bridge_test_program.rb") }
  program = space.const_get(:BridgeProgram)
  program.instance_variable_set(:@app_runtime, runtime)
  space.const_get(:GameRoomUI).install_hotkeys
  2.times { space.const_get(:GameRoomInvitationReceipts).install(program) }
  assert(legacy || runtime.managed_resources.size == 1, "repeat install duplicated its resource")
  refs = [runtime, space, program, space.const_get(:GameRoomUI),
    space.const_get(:GameRoomInvitationReceipts)].map { |object| WeakRef.new(object) }
  [runtime, backend, program, refs]
end

def close_generation(generation)
  generation[0].close_managed_resources
  generation[1].dispose
  generation[3]
end

def exercise_generations
  legacy = bridge_generation("LegacyHostBridges", legacy: true)
  depth = [EltenAPI::QuickActions.singleton_class.ancestors.length, NotificationGroups.ancestors.length]
  refs = close_generation(legacy)
  legacy = nil
  previous = nil
  20.times do |index|
    current = bridge_generation("CurrentHostBridges#{index}")
    refs.concat(close_generation(previous)) if previous
    # Late disposal of the old program cannot clear its replacement.
    assert(NotificationGroups.instance_variable_get(:@game_room_receipt_programs)["test-bridge-app"].equal?(current[2]),
      "old runtime cleanup removed current receipt registration")
    row = BridgeNotice.new(id: 301 + index, cat: "app", app_uuid: "test-bridge-app",
      date: 1, update_time: 1, revoked: false,
      payload: {"type" => "game_room.invitation_resolved", "metadata" => {}, "sender" => "Guest"}, alert: "")
    assert(Object.new.extend(NotificationGroups).build_notification_groups([row]).empty?, "technical receipt became visible")
    assert(current[2].receipts == [301 + index], "receipt did not reach current program")
    wake = row.dup
    wake.payload = row.payload.merge("type" => "game_room.tournament_changed")
    assert(Object.new.extend(NotificationGroups).build_notification_groups([wake]).empty?,
      "reload exposed a blank tournament wake")
    assert(current[2].receipts == [301 + index], "tournament wake was mistaken for an invitation receipt")
    assert([EltenAPI::QuickActions.singleton_class.ancestors.length, NotificationGroups.ancestors.length] == depth,
      "reload grew a bridge chain")
    previous = current
  end
  refs.concat(close_generation(previous))
  assert(NotificationGroups.instance_variable_get(:@game_room_receipt_programs).empty?, "unload left a registered program")
  refs
end

refs = exercise_generations
4.times { GC.start(full_mark: true, immediate_sweep: true) }
assert(refs.none?(&:weakref_alive?), "host bridge retained an unloaded namespace/program/runtime")
assert(EltenAPI::QuickActions.singleton_class.instance_variable_get(:@game_room_dispatch_bridge_version) == 3,
  "hotkey bridge was not upgraded")
assert(NotificationGroups.instance_variable_get(:@game_room_receipt_bridge_version) == 4,
  "receipt bridge was not upgraded")
puts "PASS actual host lifecycle: legacy upgrade, 20 namespaces, managed receipt cleanup, stale disposal, current delivery, WeakRef GC and stable ancestors"
