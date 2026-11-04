require 'timeout'
require_relative '../support/host_source'
require_relative '../../lib/single_instance'

def assert(value, message); raise message unless value; end

module Log
  def self.info(*); end
  def self.debug(*); end
  def self.error(message); ($handoff_errors ||= []) << message; end
end
class Scene_Main; end
class Program; end
module Programs
  def self.runtime_for(*); nil; end
  def self.with_runtime(*); yield; end
  def self.handle_execution_error(error, *); ($handoff_errors ||= []) << error; false; end
  def self.report_execution_error(error, *); ($handoff_errors ||= []) << error; false; end
end
require EltenTestHost.file('src/eapi/core/runtime.rb')
require EltenTestHost.file('src/eapi/common/threads.rb')
Object.include(EltenAPI)
native_source = EltenTestHost.file('src/eapi/program.rb')
lines = File.readlines(native_source, encoding: 'UTF-8')
first = lines.index { |line| line.strip == 'class AppNotification' }
last = ((first + 1)...lines.length).find { |i| lines[i].strip == 'class Leaderboard' } if first
raise 'Native notification class boundary changed' unless first && last
Programs.module_eval(lines[first...last].join, native_source, first + 1)

class HandoffHost
  include EltenAPI
  include EltenAPI::Common
  def prepare_keyboard_scene_transition; end
  # Only the OS frame is replaced; Core and the parallel controller are native.
  def loop_update(*)
    saved = $scene
    sleep(0.001) until Thread.current.equal?($currentthread)
    $scene = saved
    sleep(0.001)
  end
end

class HandoffProgram < Program
  class << self; attr_accessor :instances; end
  self.instances = []
  attr_accessor :run
  attr_reader :calls, :finalizations
  prepend GameRoomSingleInstance::EntryPoints
  def initialize
    @calls, @finalizations = [], []
    self.class.instances << self
  end
  def program_main; @calls << :main; run&.call; end
  def notification_action(*arguments); @calls << arguments; end
  def insert_scene(scene, must); @calls << [:launch, scene, must]; end
  def create_table_from_widget(slot); @calls << [:create, slot]; end
  def finalize(value = nil, reason: :normal)
    @finalizations << reason
    @program_finalized = true
    $scene = Scene_Main.new
    $handoff_owner_done << true if equal?($handoff_owner)
    value
  end
end

# A barrier after the first lock releases does not modify the owner or queue.
# Its callback controls the supported interleaving, never the admission result.
class HandoffLock
  def initialize(lock, owner, &after_snapshot)
    @lock, @owner, @after_snapshot = lock, owner, after_snapshot
  end
  def synchronize
    result = @lock.synchronize { yield }
    if @after_snapshot && result.is_a?(Hash) && result[:program].equal?(@owner)
      callback, @after_snapshot = @after_snapshot, nil
      callback.call(result)
    end
    result
  end
end

original_lock = GameRoomSingleInstance.instance_variable_get(:@lock)
$mainthread = $currentthread = Thread.current
$subthreads, $scenes, $handoff_errors = [], [], []
$handoff_owner_done = Queue.new
$scene = $handoff_owner = HandoffProgram.new
host = HandoffHost.new
incoming_thread = nil
barrier = HandoffLock.new(original_lock, $handoff_owner) do |owner|
  incoming_thread = Thread.current
  assert(incoming_thread.equal?($currentthread), 'Notification did not enter from the native current scene')
  $switchthread = owner[:thread] # The native Windows-menu focus mechanism.
  $handoff_owner_done.pop
end
GameRoomSingleInstance.instance_variable_set(:@lock, barrier)
initial_threads = Thread.list
switcher = Thread.new { host.send(:thr2) }
notification = Programs::AppNotification.new(id: 7, app_uuid: 'test-app',
  type: 'game_room.invitation', sender: 'Bob', created_at: 1, metadata: {})
$handoff_owner.run = -> do
  host.send(:insert_scene, Programs::NotificationActionScene.new(HandoffProgram, :open_invitation, notification), true)
end
begin
  Timeout.timeout(6) do
    host.send(:execute_scene_main, $handoff_owner)
    until incoming_thread && !incoming_thread.alive?
      raise "Native notification dispatch failed: #{$handoff_errors.inspect}" unless $handoff_errors.empty?
      sleep(0.002)
    end
  end
  incoming = HandoffProgram.instances.find { |program| !program.equal?($handoff_owner) }
  assert(incoming.calls == [[:open_invitation, notification]], 'Notification was lost or duplicated after its captured owner finished')
  assert(!incoming.instance_variable_get(:@game_room_redirected), 'New owner remained a discarded launch')
  assert(incoming.finalizations == [:notification], 'Notification did not retain normal native finalization')
  assert(GameRoomSingleInstance.active_program.nil? && $handoff_errors.empty?, 'Owner/error leaked after notification')
ensure
  switcher.kill.join
  (Thread.list - initial_threads).each { |thread| thread.kill.join }
  GameRoomSingleInstance.instance_variable_set(:@lock, original_lock)
end

# Cold widget entry after a stale snapshot still schedules a fresh scene, rather
# than executing/finalizing the reusable widget service or focusing the old UI.
owner, widget = HandoffProgram.new, HandoffProgram.new
GameRoomSingleInstance.instance_variable_set(:@active,
  {program: owner, thread: Thread.current, entry: :program_main, requests: []})
GameRoomSingleInstance.instance_variable_set(:@lock, HandoffLock.new(original_lock, owner) do
  GameRoomSingleInstance.finish_update(owner)
end)
begin
  widget.launch_game_room_entry(:create_table_from_widget, 29)
  type, scene, must = widget.calls.fetch(0)
  assert(type == :launch && must && !scene.equal?(widget), 'Retired widget owner swallowed the fresh native launch')
  assert(GameRoomSingleInstance.active_program.nil?, 'Widget callback claimed a long-lived UI owner')
  scene.program_main
  assert(scene.calls == [[:create, 29]], 'Fresh widget scene lost or duplicated the requested action')
  assert(widget.finalizations.empty?, 'Reusable widget was finalized')
ensure
  GameRoomSingleInstance.instance_variable_set(:@lock, original_lock)
end

# Another owner can appear in the same gap: use its queue, not the retired one.
retired, successor, incoming = HandoffProgram.new, HandoffProgram.new, HandoffProgram.new
old_lease = {program: retired, thread: Thread.current, entry: :program_main, requests: []}
new_lease = {program: successor, thread: Thread.current, entry: :program_main, requests: []}
GameRoomSingleInstance.instance_variable_set(:@active, old_lease)
GameRoomSingleInstance.instance_variable_set(:@lock, HandoffLock.new(original_lock, retired) do
  GameRoomSingleInstance.finish_update(retired)
  original_lock.synchronize { GameRoomSingleInstance.instance_variable_set(:@active, new_lease) }
end)
begin
  incoming.notification_action(:open_invitation, 9)
  assert(old_lease[:requests].empty? && new_lease[:requests] == [[:notification_action, [:open_invitation, 9]]],
    'Changed owner received the wrong request queue')
  successor.dispatch_game_room_entry
  assert(successor.calls == [[:open_invitation, 9]] && incoming.calls.empty?, 'Successor did not dispatch exactly once')
ensure
  GameRoomSingleInstance.instance_variable_set(:@lock, original_lock)
  GameRoomSingleInstance.finish_update(successor)
end
puts 'PASS single-instance handoff: native notification, cold widget launch and successor admission'
