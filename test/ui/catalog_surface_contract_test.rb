require_relative '../support/room_interface'
require_relative '../support/private_simulation'
require_relative '../support/model_contract'

include GameRoomTest::Assertions

# Exercise the shared factories with actual game classes and their own
# recorded action histories. New optional services/hand features must not
# become required constructor arguments or fields in unrelated games.
catalog = GameRoomGames::CATALOG
class CatalogSurfaceProgram < Program
  # Audio allocation is outside this contract; unavailable optional recordings
  # have the native API's nil result. Constructors themselves stay real.
  def create_sound_from_asset(_name, **_options); nil; end
  def read_json(path, default:); self.class.read_json(path, default: default); end
end
program = CatalogSurfaceProgram.new
services = {transport: Object.new, server_tables: Object.new,
  presentation_busy: -> { false }, future_optional_service: Object.new}
client_ids = []
roster_checks = 0
catalog.ids.each do |id|
  game = catalog.build(id)
  client = game.build_client(program, **services)
  client_ids << id if client
  client&.close
  # The start form now checks variant-specific rules before the generic
  # player-count message. Even an empty/overfull roster must be safe here.
  original_options = game.table_creation_options
  options_before = GameRoomTest::ContractValues.digest(original_options)
  (0..game.maximum_players + 1).each do |count|
    players = Array.new(count) { |seat| "Player #{seat + 1}" }
    options = game.options_for_team_roster(game.new_game_options(original_options), players: players)
    error = game.validation_error(options, player_count: count)
    assert(error.nil? || error.is_a?(String), "#{id}: invalid start-validation result")
    roster_checks += 1
  end
  assert_equal(options_before, GameRoomTest::ContractValues.digest(original_options), "#{id}: validation mutated defaults")
  next if id == 'duck_racing'

  assert_equal(false, game.paced_event_presentation?, "#{id}: inherited Duck pacing")
  assert_equal(false, game.replay_participant_transitions?, "#{id}: inherited Duck seat replay")
  assert_equal(game, game.build_presentation_game, "#{id}: replaced a custom presentation model")
end
assert_equal(%w[audio_ball axel_pong duck_racing krowa scrabble], client_ids.sort)

cases = JSON.parse(File.read(File.join(__dir__, '../fixtures/contracts/v1/histories.json'), encoding: 'UTF-8')).fetch('cases')
cases.reject! { |item| item.fetch('game') == 'tysiac' }
%w[v2/tysiac v1/mille_bornes v1/bridge].each do |name|
  cases << JSON.parse(File.read(File.join(__dir__, "../fixtures/contracts/#{name}.json"), encoding: 'UTF-8'))
end

checks = Hash.new(0)
types = Hash.new(0)
inspect_view = lambda do |game, replay, viewer|
  before = GameRoomTest::ContractValues.digest(replay)
  view = game.game_view_spec(replay, viewer)
  # Construct the whole shared layout, not just a declaration of its fields.
  layout = GameRoomLayout::Screen.new(view_spec: view, chat_text: 'Keep this draft',
    chat_index: 4, chat_check: 8, history_items: [], user_items: replay.players)
  surface = layout.surface
  types[surface.class.name] += 1
  if surface.respond_to?(:state)
    state = surface.state
    rebuilt = GameSurfaces.build(view.surface, state: state) if view.surface
    assert_equal(state, rebuilt.state, "#{game.id}: reconstructing #{surface.class} lost state") if rebuilt
    if surface.respond_to?(:reusable_for?) && surface.reusable_for?(view.surface)
      surface.update_spec(view.surface)
      assert_equal(state, surface.state, "#{game.id}: unchanged refresh moved selection")
    end
  end
  assert_equal('Keep this draft', layout.chat.text, "#{game.id}: building a game changed chat")
  assert_equal(before, GameRoomTest::ContractValues.digest(replay), "#{game.id}: presentation mutated replay")
  checks[game.id] += 1
  layout.begin_bindings
end

cases.each do |item|
  game = catalog.build(item.fetch('game'))
  env = GameRoomTest::PrivateSimulation.new_game(game: game, players: item.fetch('players'),
    options: item.fetch('options'), seed: item.fetch('seed'))
  # Every accepted prefix covers deals, choices, ordinary updates and any
  # completion in the corpus, for players and for an unrelated spectator.
  item.fetch('events').length.succ.times do |length|
    replay = game.replay(env.session, item.fetch('events').first(length), env.repository)
    (item.fetch('players') + ['Spectator']).each { |viewer| inspect_view.call(game, replay, viewer) }
  end
  assert_equal(item.fetch('events'), game.replay(env.session, item.fetch('events'), env.repository).accepted_events,
    "#{game.id}: surface coverage must use an accepted history, not a rejected fixture")
end

%w[axel_pong audio_ball duck_racing].each do |id|
  game = catalog.build(id)
  env = GameRoomTest::PrivateSimulation.new_game(game: game, players: %w[Alice Bob])
  %w[Alice Bob Spectator].each { |viewer| inspect_view.call(game, env.replay, viewer) }
end
assert_equal(catalog.ids.sort, checks.keys.sort, 'Every catalog game must cross the shared UI boundary')
puts "PASS catalog clients: #{catalog.ids.length} factories; #{client_ids.length} real clients accept optional services"
puts "PASS catalog start validation: #{roster_checks} empty/valid/overfull rosters"
puts "PASS catalog surfaces: #{checks.values.sum} player/spectator views across #{checks.length} games; #{types.length} surface families"
checks.sort.each { |id, count| puts "  #{id}: #{count}" }
