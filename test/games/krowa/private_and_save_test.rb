require_relative "../../support/krowa"
require_relative "../../support/native_live_sessions"
require_relative "../../../games/krowa_support/private_reveal"
require_relative "../../../lib/saved_games"

# Exercise the native addressed-message contract (including authoritative
# sender and recipient metadata), without sending anything to live accounts.
class NativeLiveSessionsBroker::View
  Message = Struct.new(:recipient_user) { def private?; true; end }
  attr_accessor :drop_private
  def on_message(with_metadata:, &block); (@private_callbacks ||= []) << block; end
  def receive_private(sender, payload, info)
    @private_callbacks.to_a.each { |callback| callback.call(sender, payload, info) }
  end
  def send_private(recipient, payload, **_options)
    return true if drop_private
    sender = @core.participants.fetch(user.downcase)
    @core.views.select { |view| view.user.casecmp(recipient).zero? }.each do |view|
      view.receive_private(sender, payload, Message.new(recipient))
    end
    true
  end
end

broker = NativeLiveSessionsBroker.new
transports = %w[Alice Bob Carol].to_h { |name| [name, GameRoomTransport.new(ProgramDouble.new(broker.endpoint(name)))] }
owner = transports.fetch("Alice")
table = owner.create_room(name: "Krowa private regression", game: "krowa", owner: "Alice", game_options: "{}")
%w[Bob Carol].each do |name|
  transport = transports[name]
  assert(transport.establish_membership(table_id: table["__id"], owner: "Alice", capacity: 8,
    user: name, table: transport.discover_rooms.first), "join failed")
end
run = KrowaTestGame.new(variant: "race", players: %w[Alice Bob Carol])
run.context.table_id = table["__id"]
run.automatic; run.surrender("Bob")
time = 1.0
channels = transports.to_h { |name, transport| [name, GameRoomGames::KrowaPrivateReveal.new(run.game, transport, clock: -> { time })] }
contexts = transports.to_h do |name, _|
  context = run.context.dup
  context.hidden_submissions = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new) unless name == "Alice"
  [name, context]
end
stack_before = JSON.generate(broker.cores.values.first.entries)
channels["Alice"].update(run.replay, "Alice", contexts["Alice"])
broker.cores.values.first.views.find { |view| view.user == "Bob" }.drop_private = true
channels["Bob"].update(run.replay, "Bob", contexts["Bob"])
channels["Alice"].update(run.replay, "Alice", contexts["Alice"])
assert(channels["Bob"].word.nil?, "lost request manufactured a solution")
time += 5
broker.cores.values.first.views.find { |view| view.user == "Bob" }.drop_private = false
assert(channels["Bob"].due?, "request did not become retryable")
channels["Bob"].update(run.replay, "Bob", contexts["Bob"])
assert(channels["Alice"].due?, "host not woken by private request")
channels["Alice"].update(run.replay, "Alice", contexts["Alice"])
channels["Bob"].update(run.replay, "Bob", contexts["Bob"])
channels["Carol"].update(run.replay, "Carol", contexts["Carol"])
assert(channels["Bob"].word == "kot" && channels["Carol"].word.nil?, "addressed solution leaked or lost")
assert(JSON.generate(broker.cores.values.first.entries) == stack_before, "private solution wrote public stack")
assert(!JSON.generate(run.replay.state).include?('"kot"'), "surrender word leaked into replay")

# An active participant or a public/forged message cannot request the secret.
packet = {"game" => "krowa", "action" => "request", "round" => 1, "commitment" => run.replay.state[:commitment]}
transports["Carol"].send_private_game(table_id: table["__id"], session_id: 10,
  recipient: "Alice", payload: packet, message_id: "test-request")
channels["Alice"].update(run.replay, "Alice", contexts["Alice"])
assert(!transports["Carol"].private_game_messages_pending?(table["__id"], 10), "host sent solution to active player")
bob_view = broker.cores.values.first.views.find { |view| view.user == "Bob" }
outer = {"type" => "game_room_private", "version" => 1, "session_id" => 10, "payload" => packet}
public_info = Struct.new(:recipient_user).new("Bob")
def public_info.private?; false; end
bob_view.receive_private(NativeLiveSessionsBroker::Participant.new(user: "Alice"), outer, public_info)
assert(!transports["Bob"].private_game_messages_pending?(table["__id"], 10), "public message accepted as private")
bob_view.receive_private(NativeLiveSessionsBroker::Participant.new(user: "Alice"), outer,
  NativeLiveSessionsBroker::View::Message.new("Carol"))
assert(!transports["Bob"].private_game_messages_pending?(table["__id"], 10), "wrong recipient accepted")

%w[race tower].each do |variant|
  case_run = KrowaTestGame.new(variant: variant, players: %w[Alice Bob])
  case_run.automatic
  case_run.guess("Alice", "las"); case_run.automatic
  storage = case_run.program
  saves = SavedGames.new(storage, owner: "Alice")
  snapshot = Struct.new(:session, :events).new(case_run.session, case_run.events)
  row = saves.put(game: case_run.game, table: {"owner" => "Alice", "name" => "Krowa"},
    snapshot: snapshot, repository: case_run.repository, now: case_run.context.now.to_i + 1)
  assert(row["private_data"]["payload"]["word"] == "kot", "secret missing from private archive")
  assert(SavedGames.new(storage, owner: "Bob").list.empty?, "other account reads save")
  bad = Marshal.load(Marshal.dump(row)); bad.delete("private_data"); bad["checksum"] = saves.send(:checksum, bad)
  begin
    saves.validate(bad, game: case_run.game)
    raise "missing secret accepted"
  rescue ArgumentError
  end
  bad = Marshal.load(Marshal.dump(row)); bad["private_data"]["nonce"] = "0" * 64
  bad["checksum"] = saves.send(:checksum, bad)
  begin
    saves.validate(bad, game: case_run.game)
    raise "corrupt secret accepted"
  rescue ArgumentError
  end
  restored = saves.restored_data(row, game: case_run.game, table_id: 77, now: 1_900_000_000)
  assert(!restored[:events].any? { |event| event["value"] == "kot" }, "restored public events contain secret")
  case_run.context.session_id = 999
  case_run.context.now += 1
  assert(case_run.guess("Bob", "dom") == :ok, "restored guess fixture")
  assert(case_run.automatic == :missing_secret, "fixture failed to reproduce old session bug")
  restored.fetch(:before_publish).call(999)
  assert(case_run.automatic == :ok, "secret not rebound to new session for #{variant}")
  storage.fail_write = true
  # Restoring uses the production store directly, not the fixture's subclass.
  # Make both temporary destinations unwritable without locking the originals.
  [HiddenSubmissions::ProgramStorage::DEFAULT_PATH,
    HiddenSubmissions::ProgramStorage::DEFAULT_PATH + '.recovery.json'].each do |name|
    Dir.mkdir(storage.data_path(name) + ".tmp-#{Process.pid}-#{Thread.current.object_id}")
  end
  begin
    restored.fetch(:before_publish).call(1000)
    raise "failed secret persistence accepted"
  rescue HiddenSubmissions::StorageError
  end
end

# Failed restore callback must run before ANY publicly visible archive/start.
$game_room_test_user = "Alice"
core = broker.cores.values.first
before = core.entries.length
begin
  owner.start_game(table: table, game: "krowa", players: %w[Alice Bob Carol], options: "{}", actor: "Alice",
    restore: {events: [], before_publish: ->(_) { raise IOError, "test secret failed" }})
  raise "restore failure swallowed"
rescue IOError
end
assert(core.entries.length == before && !core.closed, "failed restore published or closed table")
puts "Krowa: addressed private reveal, retry, access boundaries, Race/Tower private saves and atomic publication OK"
