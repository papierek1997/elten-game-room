require_relative '../support/duck_challenge_native'
require_relative '../support/assertions'
require_relative '../support/private_simulation'
require_relative '../../lib/game_layout'
require_relative '../../lib/game_shortcut_bindings'
require_relative '../../games/kosciane'
require_relative '../../games/balut'
include GameRoomTest::Assertions

driver = DuckChallengeNativeDriver.new
checks = 0
%w[kosciane balut yahtzee].each do |id|
  type = {'kosciane' => GameRoomGames::Kosciane, 'balut' => GameRoomGames::Balut, 'yahtzee' => GameRoomGames::Yahtzee}.fetch(id)
  game = type.new
  environment = GameRoomTest::PrivateSimulation.new_game(game: game, players: %w[Alice Bob], seed: 5)
  [0, 3].each do |rolls|
    if rolls == 3
      3.times do
        roll = environment.legal_actions.find { |action| action['action'] == 'roll' }
        assert(roll && environment.step(roll) == :ok, "#{id}: could not prepare an accepted third roll")
      end
    end
    replay = environment.replay
    %w[Alice Bob Observer].each do |viewer|
      layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay, viewer), user_items: %w[Alice Bob], history_items: ['Keep this history'])
      shortcuts = game.game_shortcuts(replay, viewer)
      expected = shortcuts.find { |key| key.key == 't' && key.modifiers.empty? }
      assert(expected && !expected.message.to_s.empty?, "#{id}/#{viewer}: missing T")
      observed = []
      GameRoomShortcutBindings.bind(layout.form, layout.shortcut_fields, shortcuts,
        consume: ->(_key) { EltenAPI::KeyboardState.clear_current_frame }) do |key|
        observed << key.message
        speak(key.message)
      end
      state_before = Marshal.dump(replay.state)
      layout.shortcut_fields.each do |field|
        layout.form.index = layout.form.fields.index(field)
        observed.clear
        SpeechOutput.reset
        driver.frame(layout.form, driver.tap(0x54), characters: 't')
        driver.frame(layout.form)
        assert_equal([expected.message], observed, "#{id}/#{rolls}/#{viewer}/#{field.class}: native T did not fire exactly once")
        assert_equal([expected.message], SpeechOutput.calls.map(&:first), "#{id}: T reread unrelated field text")
        assert(GameRoomContextHelp.field_tips(field).include?(GameRoomContextHelp.shortcut_tip('T', expected.label)),
          "#{id}: the active control did not advertise T")
        checks += 1
      end
      layout.chat.set_text('Unsent note: ')
      layout.form.index = layout.form.fields.index(layout.chat)
      layout.chat.index = layout.chat.check = layout.chat.text.length
      observed.clear
      driver.frame(layout.form, driver.tap(0x54), characters: 't')
      driver.frame(layout.form)
      assert(observed.empty?, "#{id}: T stole chat typing")
      assert_equal('Unsent note: t', layout.chat.text, "#{id}: chat did not receive the typed character")
      layout.form.index = layout.form.fields.index(layout.history)
      before = [layout.history.text, layout.history.index, layout.history.check]
      driver.frame(layout.form, driver.tap(0x54), characters: 't')
      driver.frame(layout.form)
      assert(observed.empty?, "#{id}: T overrode native history reading")
      assert_equal(before, [layout.history.text, layout.history.index, layout.history.check])
      assert_equal(state_before, Marshal.dump(replay.state), "#{id}: a read-only T changed game state")
      layout.begin_bindings
      $activecontrols = []
    end
  end
end
puts "PASS native T: #{checks} playfield/user controls, before roll/score grid, three games, player/opponent/observer, one dispatch, chat/history and immutable state"
