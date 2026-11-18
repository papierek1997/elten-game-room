require_relative '../support/assertions'
require_relative '../support/duck_challenge_native'
require_relative '../support/cheat'
require_relative '../../games/tic_tac_toe'
require_relative '../../games/farkle'
require_relative '../../games/axel_pong'
require_relative '../../games/kosciane'
require_relative '../../games/mahjong'
require_relative '../../games/bridge'
require_relative '../../lib/local_game_presentation'
GameRoomLocalization.cache_token.define_singleton_method(:_dump) { |_depth| raise TypeError, 'The full translation catalogs must not enter a replay digest' }
require_relative '../../lib/room_presentation'
require_relative '../../lib/table_activity_repository'
require_relative '../../lib/realtime/progress'
require_relative '../../lib/participant_menu'
include GameRoomTest::Assertions

runtime = Object.new
values = {}
runtime.define_singleton_method(:read_json) { |path, default: nil| values.fetch(path, default) }
runtime.define_singleton_method(:write_json) { |path, value| values[path] = value }
names = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Alice')
names.save('Grzegorz Turek')
other = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Bob')
repository = GameRoomTest::CheatFixture::Repository.new(%w[Alice Bob])
repository.define_singleton_method(:replay_authentication_identity) { [method(:actor_of), method(:event_id)] }
game = GameRoomGames::TicTacToe.new
session = {'options' => '{}'}
events = [{'id' => 1, 'actor' => 'Alice', 'action' => 'place', 'value' => '1,1'}]
canonical = game.replay(session, events, repository)
before = Marshal.dump([canonical, session, events])
renderer = GameRoomLocalGamePresentation.new(game, names)
view = renderer.replay(session, events, repository)
assert_equal(canonical.board, view.board)
assert_equal(canonical.players, view.players)
assert(view.history.any? { |entry| entry.text.include?('Grzegorz A1') }, 'Move does not use the first name')
assert(view.history.first.text.include?('Grzegorz Turek'), 'Initial participant list does not use the full name')
assert_equal('Grzegorz', renderer.game.send(:participant_name, 'Alice'))
assert_equal('Grzegorz Turek', renderer.game.send(:participant_full_name, 'Alice'))
assert(GameRoomParticipantMenu.participant_role_label('Alice', true, names: names).include?('Grzegorz Turek'), 'Participant context menu lost the full name')
assert(renderer.game.surface_spec(view, 'Bob').cells.flatten.any? { |label| label.to_s.include?('Grzegorz') }, 'Board owner was not rendered locally')
assert_equal(before, Marshal.dump([canonical, session, events]), 'Presentation mutated canonical state or events')
historical = renderer.replay(session, events, repository, boundary: canonical)
assert_equal(canonical.board, historical.board)
%w[kosciane mahjong].each do |id|
  subject = id == 'kosciane' ? GameRoomGames::Kosciane.new : GameRoomGames::Mahjong.new
  model_repository = id == 'mahjong' ? GameRoomTest::CheatFixture::Repository.new(['Alice']) : repository
  baseline = subject.replay(session, [], model_repository)
  local = GameRoomLocalGamePresentation.new(subject, names).replay(session, [], model_repository, boundary: baseline)
  assert_equal(Marshal.dump(baseline.state), Marshal.dump(local.state), "#{id}: object-based reducer state cannot be presented")
end
bridge = GameRoomLocalGamePresentation.new(GameRoomGames::Bridge.new, names).game
entry = bridge.turn_history_entry('Alice', {phase: :bidding, seat: 0, dummy: false}, event_id: 3)
assert(entry.text.include?('Grzegorz'), 'Bridge-owned turn labels lost the local action name')
assert_equal('Alice', game.send(:participant_name, 'Alice'))
assert(GameRoomLocalGamePresentation.new(game, other).replay(session, events, repository).history.none? { |entry| entry.text.include?('Grzegorz') }, 'Alias leaked to another receiver')
view.history.clear
assert(!renderer.replay(session, events, repository).history.empty?, 'Presentation cache shares a mutable replay')
changed = events.map(&:dup)
changed.first['value'] = '2,1'
assert(renderer.replay(session, changed, repository).history.any? { |entry| entry.text.include?('Grzegorz B1') }, 'Changed earlier input reused cached labels')
original_actor = repository.method(:actor_of)
begin
  repository.define_singleton_method(:actor_of) { |_event, _session = nil| 'Bob' }
  assert_equal([], renderer.replay(session, changed, repository).accepted_events, 'Changed authenticated actor reused the old projection')
ensure
  repository.define_singleton_method(:actor_of, original_actor)
end
turn_boundary = GameRoomSnapshot.copy(canonical)
turn_boundary.history << game.turn_transition_history_entry(nil, canonical, event_id: 1)
original_capture = GameRoomSnapshot.method(:capture)
begin
  wrapper = Struct.new(:inner) do
    def bytesize; GameRoomReplayCache::MAX_BYTES + 1; end
    def restore; inner.restore; end
  end
  GameRoomSnapshot.define_singleton_method(:capture) { |value| wrapper.new(original_capture.call(value)) }
  uncached = GameRoomLocalGamePresentation.new(game, names).replay(session, events, repository, boundary: turn_boundary)
  assert_equal(1, uncached.history.count { |entry| entry.kind == :turn }, 'Uncached projection dropped the turn history')
ensure
  GameRoomSnapshot.define_singleton_method(:capture, original_capture)
end

scores = GameRoomLocalGamePresentation.new(GameRoomGames::Farkle.new, names).game
text = scores.send(:scores_text, {players: %w[Alice Bob], scores: {'Alice' => 50, 'Bob' => 20}})
assert(text.include?('Grzegorz Turek: 50') && text.include?('Bob: 20'), 'Score names use the action form')
sport = GameRoomLocalGamePresentation.new(GameRoomGames::AxelPong.new, names).game
assert_equal(['Grzegorz Turek', 'Bob'], sport.score_labels(sport.default_options, %w[Alice Bob]))
binary_name = 'Łukasz'.b
assert_equal(Encoding::UTF_8, sport.score_labels(sport.default_options, [binary_name, 'Bob']).first.encoding)

rows = RoomPresentation.user_rows(%w[Alice Bob], owner: 'Alice', players: %w[Alice Bob], active: true,
  scores: {'Alice' => 50, 'Bob' => 20}, names: names)
assert_equal('Alice', rows.first.participant)
assert(rows.first.label.include?('Grzegorz Turek') && rows.first.label.include?('50'), 'User rows lost full names/scores')
assert(RoomPresentation.user_rows(%w[Alice Bob], owner: 'Alice', players: [], active: false, names: names).first.label.include?('Grzegorz Turek'), 'Waiting roster was not rendered')

activity = TableActivityRepository.allocate
chat = TableActivityRepository::Entry.new(id: 1, actor: 'Alice', owner: 'Alice', game: 'cheat',
  kind: 'chat', message: 'Alice wrote Grzegorz Turek, unchanged.', stack_sequence: 1, created_at: 1)
raw = Marshal.dump(chat)
local = activity.text_for(chat, game_name: ->(id) { id }, names: names)
remote = activity.text_for(chat, game_name: ->(id) { id }, names: other)
assert_equal('Grzegorz Turek: ' + chat.message, local)
assert_equal('Alice: ' + chat.message, remote)
assert_equal(raw, Marshal.dump(chat), 'Chat content or authenticated author changed')
merged = -> { activity.merged_history_entries(game_entries: [], game_events: [], activity_entries: [chat], game_name: ->(id) { id }, names: names) }
assert(merged.call.first.text.start_with?('Grzegorz Turek:'), 'History uses a canonical chat author locally')
names.save('Jan Kowalski')
assert(merged.call.first.text.start_with?('Jan Kowalski:'), 'Chat cache ignored the local revision')
names.reset
assert(merged.call.first.text.start_with?('Alice:'), 'Chat reset kept the former name')

client = Object.new.extend(GameRoomRealtime::ProgressClient)
program = Object.new
program.define_singleton_method(:local_name_presentation) { names }
client.instance_variable_set(:@program, program)
client.instance_variable_set(:@game, GameRoomGames::AxelPong.new)
client.instance_variable_set(:@viewer, 'Alice')
names.save('Anna Żółć')
assert_equal('Anna', client.receiver_participant_name('Alice'))
assert_equal('Anna Żółć', client.receiver_participant_name('Alice', form: :full))
assert_equal(['Anna Żółć', 'Bob'], client.receiver_game.score_labels(client.receiver_game.default_options, %w[Alice Bob]))
client.instance_variable_set(:@viewer, 'Bob')
assert_equal('Alice', client.receiver_participant_name('Alice'), 'A stale realtime viewer borrowed another account alias')
assert_equal(raw, Marshal.dump(chat))
puts 'PASS local presentation: canonical board/cards identity, isolated copied replay/history, exact cache input, full scores/rosters/chat, first-name objects, receiver isolation, unchanged chat/wire and realtime viewer scope'
