require_relative "../support/native_room_harness"
require_relative "../../games/quiz_party"
require_relative "../../games/categories"
require_relative "../../games/battleship"
require_relative "../../games/krowa"
require_relative "../../games/scrabble"
require_relative "../../games/uno"
require_relative "../../games/tic_tac_toe"
require_relative "../../games/makao"
require_relative "../../games/axel_pong"
require_relative "../../games/audio_ball"
require_relative "../../games/darts"
require_relative "../../lib/participant_menu"
require_relative "../../lib/game_simulation"

CapabilityReplay = Struct.new(:state, :done) do
  def finished?; done; end
end

# Test-only copy of the previous decision, independent of the new hooks.
def previous_controller_error(game, replay, replacement)
  return "This game does not support computers." if replacement && !game.supports_bots?
  return nil if replay == nil || replay.finished?
  return nil if %w[axel_pong audio_ball].include?(game.id)
  return "Wait until the current game has finished before changing its controller." unless game.session_runner?
  return "The current game contains private data that cannot be transferred at this stage." if
    %w[battleship krowa].include?(game.id) ||
    (%w[quiz categories].include?(game.id) && %i[answering revealing].include?(replay.state[:phase]))
  nil
end

types = [GameRoomGames::QuizParty, GameRoomGames::Categories, GameRoomGames::Battleship,
  GameRoomGames::Krowa, GameRoomGames::Scrabble, GameRoomGames::Uno,
  GameRoomGames::AxelPong, GameRoomGames::AudioBall]
cases = 0
types.each do |type|
  game = type.new
  replays = [nil] + %i[placing active playing answering revealing round_complete finished].flat_map do |phase|
    [false, true].map { |finished| CapabilityReplay.new({phase: phase}, finished) }
  end
  replays.each do |replay|
    [false, true].each do |replacement|
      expected = previous_controller_error(game, replay, replacement)
      assert(game.controller_change_error(replay, replacement: replacement) == expected, "#{game.id}: phase/bot error changed")
      # A renamed/reused model retains its own phase contract; no central list
      # may be needed when another identifier exposes the same model.
      original_id = game.method(:id)
      game.define_singleton_method(:id) { "new_#{original_id.call}" }
      assert(game.controller_change_error(replay, replacement: replacement) == expected, "#{type}: contract still depends on ID")
      game.singleton_class.remove_method(:id)
      cases += 1
    end
  end
end

unknown_realtime = Class.new(GameRoomGames::Base) do
  def id; "unknown_realtime"; end
  def session_runner?; false; end
end.new
assert(unknown_realtime.controller_change_error(CapabilityReplay.new(nil, false)), "unreviewed realtime model silently permits transfer")
board = GameRoomGames::TicTacToe.new
repository = GameRoomSimulation::Repository.new(%w[Alice Bob])
replay = board.replay({}, [], repository)
assert(replay.state == nil && board.controller_change_error(replay) == nil, "real nil-state board replay rejected")

program = Object.new
called = []
program.define_singleton_method(:show_pong_settings) { called << :pong }
program.define_singleton_method(:show_audio_ball_settings) { called << :audio_ball }
program.define_singleton_method(:show_darts_settings) { called << :darts }
program.define_singleton_method(:show_custom_settings) { called << :custom }
program.singleton_class.send(:private, :show_pong_settings, :show_audio_ball_settings, :show_darts_settings, :show_custom_settings)
client = Object.new
client.define_singleton_method(:show_settings) { called << :client }
[GameRoomGames::AxelPong.new, GameRoomGames::AudioBall.new, GameRoomGames::Darts.new].each do |game|
  entry = GameRoomParticipantMenu.personal_settings_entry(game)
  assert(entry.help_key == "Ctrl+P" && entry.menu_key == "p", "settings shortcut changed")
  GameRoomParticipantMenu.settings_callback(game, program: program).call
  GameRoomParticipantMenu.settings_callback(game, program: program, client: client).call
end
assert(called == [:pong, :client, :audio_ball, :client, :darts, :client], "waiting/active settings boundary changed")
assert(GameRoomParticipantMenu.settings_callback(board, program: program, client: client) == nil, "ordinary game gained personal settings")
assert(GameRoomParticipantMenu.personal_settings_entry(board) == nil, "ordinary game gained a Pong label")
extension = Class.new(GameRoomGames::Base) do
  def id; "extension"; end
  def personal_settings_action; :show_custom_settings; end
  def personal_settings_label; "Żółte ustawienia".b; end
end.new
GameRoomParticipantMenu.settings_callback(extension, program: program).call
assert(called.last == :custom, "extension settings still require a central ID whitelist")
assert(GameRoomParticipantMenu.personal_settings_entry(extension).label.encoding == Encoding::UTF_8, "binary settings label escaped UI normalization")

definition = GameRoomGames::OptionDefinition
definitions = [
  definition.new(key: "profile", kind: :choice),
  definition.new(key: "flag", kind: :boolean),
  definition.new(key: "number", kind: :integer),
  definition.new(key: "ranks", kind: :multiple_choice)
]
makao = GameRoomGames::Makao.new
assert(makao.remembered_option_definitions(definitions).map(&:key) == %w[flag number ranks], "Makao loading preferences changed")
assert(makao.remembered_option_definitions(definitions, options: {"profile" => "custom"}).map(&:key) == %w[flag number ranks], "Makao custom saving changed")
assert(makao.remembered_option_definitions(definitions, options: {"profile" => "classic"}).map(&:key) == %w[ranks], "Makao preset saving changed")
assert(board.remembered_option_definitions(definitions).map(&:key) == %w[ranks], "ordinary option persistence changed")
assert(board.remembered_option_definitions(definitions, options: {}).map(&:key) == %w[ranks], "ordinary option saving changed")

puts "PASS capability boundaries: #{cases} exact controller decisions, renamed models, nil-state board, default realtime guard, local-settings dispatch and option-memory contracts"
