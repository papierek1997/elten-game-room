# encoding: UTF-8
require_relative '../../support/ui'

def _(text); text; end

require_relative '../../../games/darts'
require_relative '../../../lib/darts/client'

def assert(value, message)
  raise message unless value
end

class DartsCursorNetwork
  attr_reader :channels

  def initialize
    @channels = []
  end

  def build(**options)
    channel = DartsCursorChannel.new(self, **options)
    @channels << channel
    channel
  end

  def deliver(sender, data)
    packet = GameRoomRealtime::Protocol.decode(data, match: sender.match, epoch: sender.epoch)
    return unless packet

    targets = @channels.select do |candidate|
      next false if candidate.equal?(sender) || candidate.closed || candidate.match != sender.match
      sender.host? || candidate.host?
    end
    targets.each { |target| target.receive(sender.viewer, packet) }
  end

  def latest(viewer)
    @channels.reverse.find { |channel| channel.viewer.casecmp?(viewer) }
  end
end

class DartsCursorChannel
  attr_reader :epoch, :match, :viewer, :sent
  attr_accessor :closed

  def initialize(network, match:, owner:, viewer:, **_options)
    @network, @match, @owner, @viewer = network, match, owner.to_s, viewer.to_s
    @epoch = 'darts-cursor-test-epoch'
    @incoming, @sent, @closed = {}, [], false
  end

  def host?; @owner.casecmp?(@viewer); end
  def tick; end
  def connected?; !@closed; end

  def send(data)
    return false if @closed
    @sent << data
    @network.deliver(self, data)
    true
  end

  def receive(sender, packet)
    @incoming[sender.downcase] = packet
  end

  def take_packets
    packets, @incoming = @incoming, {}
    packets
  end

  def close
    @closed = true
    @incoming.clear
  end
end

class DartsCursorAudio
  attr_reader :updates, :silence_calls

  def initialize
    @updates, @silence_calls = [], 0
  end

  def update(x, y, active:); @updates << [x, y, active]; end
  def silence; @silence_calls += 1; end
  def ready; end
  def deadline_warning(_seconds); end
  def edge; end
  def limit; end
  def close; end
end

class DartsCursorMouse
  def suspend; [[], false]; end
end

DartsCursorReplay = Struct.new(:current_player, :state) do
  def finished?; false; end
end

def darts_cursor_client(network, viewer, owner, clock, audio)
  client = GameRoomDarts::Client.new(Object.new, GameRoomGames::Darts.new, clock: clock,
    audio: audio, mouse: DartsCursorMouse.new,
    channel_factory: ->(**options) { network.build(**options) })
  client.bind_screen(session_id: 77, table_id: 7, owner: owner, viewer: viewer,
    members: -> { %w[Alice Bob Watcher] })
  client
end

now = 0.0
clock = -> { now }
state = {
  phase: :playing, seed: 'a' * 32, throw_index: 4, round: 2, dart: 2,
  options: {'difficulty'=>'normal', 'progressive'=>false, 'rounds'=>3,
    'time_limit'=>10, 'timeout_result'=>'auto', 'mouse_input'=>false, 'mode'=>'game'}
}
replay = DartsCursorReplay.new('Alice', state)
network = DartsCursorNetwork.new
audios = %w[Alice Bob Watcher].to_h { |name| [name, DartsCursorAudio.new] }
clients = %w[Alice Bob Watcher].to_h do |name|
  [name, darts_cursor_client(network, name, 'Watcher', clock, audios.fetch(name))]
end
initial_control = {'__frozen'=>false, '__table_owner'=>'Watcher', '__control_epoch'=>'initial',
  '__controllers'=>{}, '__players'=>%w[Alice Bob]}
clients.each_value do |client|
  client.update_table_control(initial_control)
  client.before_wait(replay, client.instance_variable_get(:@viewer))
end

alice = clients.fetch('Alice')
assert(alice.send(:start_aim, now), 'the throwing guest could not start the network cursor')
engine = alice.instance_variable_get(:@engine)
engine.instance_variable_set(:@x, 230.0)
engine.instance_variable_set(:@y, -410.0)
alice.frame
alice_position = engine.position.map(&:round)
clients.fetch('Watcher').frame
clients.fetch('Bob').frame

assert(audios.fetch('Watcher').updates.last&.first(2) == alice_position,
  'an observer table owner did not hear the throwing guest cursor')
assert(audios.fetch('Bob').updates.last&.first(2) == alice_position,
  'another player did not hear the cursor relayed by an observer owner')
remote = clients.fetch('Bob').instance_variable_get(:@remote_cursor)
assert(remote && remote[:player] == 'Alice' && [remote[:x], remote[:y]] == alice_position,
  'the relayed cursor lost its player identity or newest position')

alice_channel = network.latest('Alice')
sent_before = alice_channel.sent.length
now = 0.01
engine.instance_variable_set(:@x, 500.0)
alice.frame
assert(alice_channel.sent.length == sent_before,
  'cursor movement exceeded the bounded twenty-packets-per-second rate')
now = 0.05
alice.frame
assert(alice_channel.sent.length == sent_before + 1,
  'the cursor did not publish its newest position at the next send boundary')
clients.fetch('Watcher').frame
clients.fetch('Bob').frame

watcher_silence = audios.fetch('Watcher').silence_calls
bob_silence = audios.fetch('Bob').silence_calls
now = 0.36
clients.fetch('Watcher').frame
clients.fetch('Bob').frame
assert(audios.fetch('Watcher').silence_calls > watcher_silence && audios.fetch('Bob').silence_calls > bob_silence,
  'a lost cursor stream remained audible after its freshness timeout')

old_channels = clients.transform_values { |client| client.instance_variable_get(:@channel) }
replacement = initial_control.merge('__table_owner'=>'Bob', '__control_epoch'=>'replacement-1')
clients.each_value { |client| client.update_table_control(replacement) }
assert(old_channels.values.all?(&:closed), 'table-owner replacement left an old Darts channel open')
assert(clients.values.all? { |client| client.instance_variable_get(:@remote_cursor) == nil },
  'table-owner replacement retained a cursor from the previous control epoch')
assert(network.latest('Bob').host?, 'the replacement table owner did not become the cursor relay')
assert(alice.instance_variable_get(:@awaiting_start_identity),
  'control replacement did not safely restart the unfinished local aiming gate')

alice.update_table_control(replacement.merge('__frozen'=>true))
assert(alice.instance_variable_get(:@awaiting_start_identity) == nil,
  'a durable table pause left the local aiming gate active')
alice.update_table_control(replacement.merge('__frozen'=>false))
assert(alice.instance_variable_get(:@awaiting_start_identity),
  'resuming a durable table pause did not restore a fresh aiming gate')

clients.each_value(&:close)

# The ordinary case remains direct: an active owner publishes snapshots to all
# other table members without hearing a network echo of their own locator.
now = 1.0
direct_network = DartsCursorNetwork.new
direct_audio = {'Alice'=>DartsCursorAudio.new, 'Bob'=>DartsCursorAudio.new}
direct = direct_audio.to_h do |name, audio|
  [name, darts_cursor_client(direct_network, name, 'Alice', clock, audio)]
end
direct.each do |name, client|
  client.before_wait(replay, name)
end
direct_alice = direct.fetch('Alice')
assert(direct_alice.send(:start_aim, now), 'the owner could not start a directly published cursor')
direct_engine = direct_alice.instance_variable_get(:@engine)
direct_engine.instance_variable_set(:@x, -125.0)
direct_engine.instance_variable_set(:@y, 375.0)
direct_alice.frame
direct.fetch('Bob').frame
assert(direct_audio.fetch('Bob').updates.last&.first(2) == direct_engine.position.map(&:round),
  'a player did not hear the active table owner cursor')

direct.each_value(&:close)
puts 'PASS Darts network cursor: observer relay, direct owner, rate limit, timeout and control replacement'
