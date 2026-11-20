require_relative '../support/duck_challenge_native'
require_relative '../../games/poker'
require_relative '../../lib/game_screen'

Session.define_singleton_method(:name) { 'Alice' }
game = GameRoomGames::Poker.new
repository = Struct.new(:players) { def players_for(_); players; end }.new(%w[Alice Bob])
initial = game.replay({'options' => JSON.generate(game.default_options)}, [], repository)

[[false, false, true], [true, true, true], [true, false, false]].each do |frozen, manual, expected|
  driver = DuckChallengeNativeDriver.new
  replay = GameRoomSnapshot.copy(initial)
  replay.state[:phase] = :hand_complete
  replay.state[:hand_resume_at] = 105
  session = {'__frozen' => frozen, '__round_pause' => manual}
  screen = GameScreen.allocate
  screen.instance_variable_set(:@game, game)
  screen.instance_variable_set(:@repository, repository)
  screen.instance_variable_set(:@session, session)
  screen.instance_variable_set(:@table_owner, 'Alice')
  screen.instance_variable_set(:@session_runner, Object.new)
  screen.define_singleton_method(:event_presentation_busy?) { false }
  screen.define_singleton_method(:action_context) { GameRoomGames::ActionContext.new(now: manual ? 999 : 101) }
  layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay, 'Alice'), user_items: %w[Alice Bob])
  wait = GameScreen::WaitState.new(replay: replay)
  remembered = 0
  screen.send(:bind_wait_shortcuts, wait, layout, -> { remembered += 1 })
  driver.frame(layout.form, driver.tap(0x50, modifiers: [0x10]), held: [], characters: 'P')
  assert((wait.action == :toggle_round_pause) == expected, "Shift+P: frozen=#{frozen}, manual=#{manual}, action=#{wait.action}")
  assert(remembered == (expected ? 1 : 0), 'Pause moved focus or dispatched more than once')
  next unless expected
  # In an actual text field the same character remains ordinary text input.
  wait.action = nil
  layout.form.index = layout.form.fields.index(layout.chat)
  layout.chat.set_text('Draft')
  driver.frame(layout.form)
  driver.frame(layout.form, driver.tap(0x50, modifiers: [0x10]), characters: 'P')
  assert(wait.action.nil?, 'Typing uppercase P in chat toggled the game pause')
  assert(layout.chat.text.include?('Draft') && layout.chat.text.include?('P'), 'Pause handling ate chat input')
end
$activecontrols = []
puts 'PASS native Shift+P: one pause/resume dispatch, manual versus technical freeze, retained focus and ordinary uppercase chat input'
