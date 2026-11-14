require_relative '../support/settings_widget'
require_relative '../support/assertions'
include GameRoomTest::Assertions

class FixedStartOptionsApp < EltenGameRoom
  attr_reader :prepared

  def run_network_task(*, **); yield; end
  def alert(message); raise message; end
  def missing_live_session_members(_room); []; end
  def start_prepared_game(_row, state:, game:, participants:, options:, refreshed_room:)
    @prepared = options
  end
end

game = GameRoomGames::TicTacToe.new
legacy = game.default_options
fresh = game.table_creation_options
assert(!legacy.key?('random_start'), 'The legacy fixture already opts into new rules')
assert_equal(1, fresh['random_start'])

[nil, {'fixture' => 'fixed tournament binding'}].each do |marker|
  [legacy, fresh].each do |stored|
    table = {'__id' => 7, '__live_session_id' => 'fixture-room', 'owner' => 'Alice',
      'game' => game.id, 'game_options' => JSON.generate(stored), 'status' => 'waiting'}
    table['tournament_match'] = marker if marker
    room = LobbyRepository::TableSnapshot.new(table: table, members: %w[Alice Bob], bots: [], observers: [])
    state = GameRoomLifecycle::State.new(room: room, game: game, game_snapshot: nil, replay: nil)
    lobby = Object.new
    lobby.define_singleton_method(:owner_of) { |row| row.fetch('owner') }
    lobby.define_singleton_method(:snapshot_for) { |*, **| room }
    lobby.define_singleton_method(:playing?) { |_| false }
    app = FixedStartOptionsApp.new
    app.instance_variable_set(:@lobby, lobby)
    input = Marshal.dump(stored)
    app.send(:start_new_game, table, state: state)
    expected = marker ? stored : game.new_game_options(stored)
    assert_equal(expected, app.prepared, 'The real Start handler changed fixed tournament options')
    assert_equal(input, Marshal.dump(stored), 'Start preparation mutated the stored options')
  end
end

# The same boundary applies to every game, not just the new starter draw.
GameRoomGames::CATALOG.ids.each do |id|
  model = GameRoomGames::CATALOG.build(id)
  stored = model.default_options
  players = Array.new(model.minimum_players) { |index| "Player#{index}" }
  expected = model.options_for_team_roster(model.normalize_options(stored), players: players)
  assert_equal(expected, model.game_start_options(stored, players: players, fixed: true), "#{id}: fixed options were upgraded")
  expected = model.options_for_team_roster(model.new_game_options(stored), players: players)
  started = model.game_start_options(stored, players: players)
  if id == 'billiards'
    seed = started.fetch('rack_seed')
    assert(seed.is_a?(Integer) && seed.between?(0, 2**31 - 1), 'A new billiards game has no valid rack seed')
    expected['rack_seed'] = seed
  end
  assert_equal(expected, started, "#{id}: ordinary new-game defaults were lost")
end
puts 'PASS fixed start options: real Start handler, old/new tournament bindings, ordinary defaults and the complete game catalogue'
