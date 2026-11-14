require_relative "../support/ui"
require_relative "../support/log"
require_relative "../support/native_live_sessions"
class Program
  def self.server_app(**_options); end
end
require_relative "../../__app"
require_relative "../support/private_simulation"
require_relative "../support/native_simulation"
require_relative '../support/catalog_options'

$stdout.sync = true
checked = []
EltenGameRoom::GAME_REGISTRY.ids.each do |id|
  game = EltenGameRoom::GAME_REGISTRY.build(id)
  # Private answer/board protocols are covered by controller_phase_safety;
  # this pure replay fixture intentionally has no secret-answer vault.
  next if %w[quiz categories battleship krowa].include?(id)
  next unless game.session_runner? && (game.supports_bots? || id == 'scrabble')
  options = GameRoomTest::CatalogOptions.for_players(game, bots: game.supports_bots?).merge('bot_delay' => 0)
  count = ([game.minimum_players, 2].max..game.maximum_players).find { |n| !game.validation_error(options, player_count: n) }
  players = %w[Alice Bob Carol Dave Eve Frank Grace Heidi].first(count)
  # Native-only draws need their native metadata and real timestamps, not the
  # older corpus's event-count clock. Both use the unchanged production reducer.
  simulation = id == 'cash_auction' ? GameRoomTest::NativeSimulation : GameRoomTest::PrivateSimulation
  env = simulation.new_game(game: game, players: players, options: options, seed: 137)
  2.times do
    break if env.finished?
    actor = env.active_actor
    action = env.legal_actions(actor).first
    break unless action
    assert(env.step(action, actor: actor) == :ok, "#{id}: failed to prepare an ordinary move")
  end
  next if env.finished? || game.controller_change_error(env.replay)
  before = env.replay
  swapped = players.dup
  swapped[0], swapped[1] = swapped[1], swapped[0]
  variants = [swapped]
  variants << ['bot:1:1:pl20', *players.drop(1)] if game.supports_bots?
  variants.each do |roster|
    boundary = env.events.map { |event| event['id'] }.max.to_i + 1
    session = env.session.merge('__players' => roster, '__initial_players' => players,
      '__seat_changes' => [{'id' => boundary, 'players' => roster}])
    after = simulation.new(game: game, session: session,
      events: Marshal.load(Marshal.dump(env.events)), players: roster,
      random_source: GameRoomRandom::SeededSource.new(241))
    after.instance_variable_set(:@next_event_id, boundary + 1)
    assert(after.replay.players == roster, "#{id}: current participants not replaced")
    assert(after.replay.history.map(&:to_h) == before.history.map(&:to_h), "#{id}: historical messages rewritten")
    assert(after.replay.accepted_events == env.events, "#{id}: previous actions rejected/rewritten")
    actor = after.active_actor
    action = after.legal_actions(actor).first
    assert(after.step(action, actor: actor) == :ok, "#{id}: next occupant's action rejected") if action
    again = game.replay(session, after.events, after.repository)
    assert(again.accepted_events == after.events && again.history.first(before.history.length).map(&:to_h) == before.history.map(&:to_h), "#{id}: continuation or historical names diverged")
  end
  checked << id
  puts "#{id}: mid-game replacement/swap, historical messages and continuation OK"
end
assert(checked.size >= 20, 'Too few actual game models tested')
puts "Mid-game participant replay contracts: #{checked.size} games OK"
