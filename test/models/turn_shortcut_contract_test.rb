require_relative '../support/assertions'
require_relative '../../games/catalog'
require_relative '../support/private_simulation'
include GameRoomTest::Assertions

# A sequential game must not lose T by replacing the optional feature list,
# or by muting automatic turn announcements to avoid repetitive speech.
class QuietTurnShortcutGame < GameRoomGames::Base
  def id; 'quiet_turn_test'; end
  def name; 'Quiet turn test'; end
  def shortcut_features; []; end
  def turn_announcement(_replay, _viewer); nil; end
end

game = QuietTurnShortcutGame.new
replay = GameRoomGames::Replay.new(players: %w[Alice Bob], current_player: 'Alice', state: {phase: :playing})
turn = ->(g, r, viewer) { g.game_shortcuts(r, viewer).find { |key| key.key == 't' && key.modifiers.empty? } }
assert_equal('It is your turn.', turn.call(game, replay, 'Alice')&.message,
  'Replacing optional features/silent automatic speech removed the shared T command')
assert_equal("It is Alice's turn.", turn.call(game, replay, 'Observer')&.message)
assert_equal(nil, game.turn_announcement(replay, 'Alice'), 'Explicit T restored unwanted automatic speech')

{bidding: ['You are bidding.', 'Alice is bidding.'],
 review: ['You are reviewing the answers.', 'Alice is reviewing the answers.'],
 choosing: ['Choose a category.', 'Alice is choosing a category.']}.each do |phase, messages|
  replay.state[:phase] = phase
  assert_equal(messages[0], turn.call(game, replay, 'Alice').message)
  assert_equal(messages[1], turn.call(game, replay, 'Observer').message)
end

class CustomTurnShortcutGame < QuietTurnShortcutGame
  def custom_game_shortcuts(_replay, _viewer)
    [GameRoomGames::GameShortcut.new(key: 't', kind: :announcement, label: 'Current role', message: 'Keep the role-specific command')]
  end
end
custom = CustomTurnShortcutGame.new
assert_equal('Keep the role-specific command', turn.call(custom, replay, 'Alice').message)
assert_equal(1, custom.game_shortcuts(replay, 'Alice').count { |key| key.key == 't' && key.modifiers.empty? })

replay.winner = 'Alice'
assert(turn.call(game, replay, 'Observer').message.to_s.include?('Alice'), 'Finished game lost its explicit result command')
replay.winner = nil
replay.current_player = nil
assert_equal(nil, turn.call(game, replay, 'Alice'), 'A no-turn activity acquired an unrelated command')

checked = 0
GameRoomGames::CATALOG.ids.each do |id|
  subject = GameRoomGames::CATALOG.build(id)
  options = subject.default_options
  count = (subject.minimum_players..subject.maximum_players).find { |n| !subject.validation_error(options, player_count: n) }
  players = %w[Alice Bob Carol Dave Eve Frank Grace Heidi].first(count)
  environment = GameRoomTest::PrivateSimulation.new_game(game: subject, players: players, options: options, seed: 7)
  current = environment.replay
  next unless current.current_player

  [players.first, current.current_player, 'Observer'].uniq.each do |viewer|
    shortcut = turn.call(subject, current, viewer)
    assert(shortcut && !shortcut.message.to_s.empty?, "#{id}/#{viewer}: an active game has no usable T command")
  end
  checked += 1
end
puts "PASS shared explicit-turn contract: optional features, quiet automatic speech, phases, custom roles, observer, result and #{checked} active catalogue games"
