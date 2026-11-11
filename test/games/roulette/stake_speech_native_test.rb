require_relative '../../support/duck_challenge_native'
require EltenTestHost.file('src/ui/dialogs.rb')
require_relative '../../../games/roulette'
require_relative '../../../lib/game_screen'

# Use native list/update, EditBox, Form, KeyboardState and speech sequencing.
# Only the output device is replaced; the stake dialog is not stubbed.
module SpeechOutput
  def self.speak_sequence(sequence)
    speak_text(sequence.text, method: 1, interrupt: true)
  end
end

Session.define_singleton_method(:name) { 'Alice' }
repository = Struct.new(:players) { def players_for(_session); players; end }.new(%w[Alice Bob])

%w[en pl cs es ru].each do |language|
  driver = DuckChallengeNativeDriver.new
  GameRoomLocalization.boot(settings: {'interface_language' => language, 'known_languages' => [language]}, host_language: language)
  assert(GameRoomLocalization.primary_language == language, "Missing catalog: #{language}")
  game = GameRoomGames::Roulette.new
  replay = game.replay({'options' => JSON.generate(game.default_options)}, [], repository)
  screen = GameScreen.allocate
  screen.instance_variable_set(:@game, game)
  screen.instance_variable_set(:@session, {})
  screen.define_singleton_method(:event_presentation_busy?) { false }
  layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay, 'Alice'), user_items: repository.players)
  wait = GameScreen::WaitState.new(replay: replay)
  screen.send(:bind_wait_surface, wait, layout, -> {})
  mode, frames, fields, dialog_speech = :confirm, 0, [], []
  driver.define_singleton_method(:tick) do |form|
    frames += 1
    raise "#{language}: stake dialog failed to close" if frames > 30
    if form.instance_variable_get(:@wait)
      field = form.fields.first
      assert(form.fields.size == 1 && field.is_a?(EditBox), "#{language}: stake did not use one native edit field")
      assert(!fields.include?(field), "#{language}: same stake field requested another input")
      fields << field
      assert(field.text == '10' && [field.index, field.check].minmax == [0, 2], "#{language}: suggested stake is not selected")
      assert(SpeechOutput.calls.one? && SpeechOutput.calls.first.first.include?(field.header),
        "#{language}: stake prompt or unrelated status was repeated: #{SpeechOutput.calls.inspect}")
      dialog_speech << SpeechOutput.calls.first.first
      field.set_text('17') if mode == :confirm
      snapshot(tap(mode == :confirm ? 0x0D : 0x1B), [])
    else
      snapshot([], [])
    end
  end
  control = layout.surface.fields.first
  group = game.surface_spec(replay, 'Alice').items.index { |item| item.id == 'bets:colours' }
  control.index = group
  # Entering the table may read its status. Opening its local bet category
  # must instead read only the selected bet, once.
  layout.form.focus
  SpeechOutput.reset
  driver.frame(layout.form, driver.tap(0x0D))
  assert(layout.surface.state['menu'] == 'bets:colours' && wait.action.nil?, "#{language}: category submitted a move")
  assert(SpeechOutput.calls.one? && SpeechOutput.calls.first.first.strip == control.options.first,
    "#{language}: category repeated the table status: #{SpeechOutput.calls.inspect}")
  driver.frame(layout.form)
  SpeechOutput.reset
  driver.frame(layout.form, driver.tap(0x0D))
  selected = screen.instance_variable_get(:@selected_surface_action)
  assert(wait.action == :game_action && selected.to_h.values_at('bet', 'amount') == ['red', 17], "#{language}: Enter changed the selected bet")
  assert(SpeechOutput.calls.size == 1, "#{language}: confirmation reread the list/status: #{SpeechOutput.calls.inspect}")
  assert(!screen.send(:dialog_opened) && !EltenAPI::KeyboardState.current.pressed[0x0D], "#{language}: confirmed dialog leaked its Enter")

  wait.action = nil
  screen.instance_variable_set(:@selected_surface_action, nil)
  mode, frames = :cancel, 0
  driver.frame(layout.form, driver.tap(0x28))
  assert(control.index == 1, "#{language}: cannot select the next bet after the dialog")
  SpeechOutput.reset
  driver.frame(layout.form, driver.tap(0x0D))
  assert(wait.action.nil? && screen.instance_variable_get(:@selected_surface_action).nil?, "#{language}: Escape placed a bet")
  assert(layout.surface.state['menu'] == 'bets:colours' && control.index == 1, "#{language}: Escape lost the selected bet")
  assert(SpeechOutput.calls.one? && !screen.send(:dialog_opened), "#{language}: cancellation repeated or retained the dialog")
  assert(!EltenAPI::KeyboardState.current.pressed[0x1B], "#{language}: Escape leaked into the underlying list")

  SpeechOutput.reset
  layout.back_button.press
  assert(wait.action.nil? && !layout.surface.cancel_pending_action? && control.index == group, "#{language}: category return lost focus")
  assert(SpeechOutput.calls.one? && SpeechOutput.calls.first.first.strip == control.options[group],
    "#{language}: category return repeated table status: #{SpeechOutput.calls.inspect}")
  assert(fields.size == 2 && dialog_speech.size == 2, "#{language}: incorrect number of actual stake dialogs")
end
$activecontrols = []
puts 'PASS native roulette speech: five catalogs, actual Enter/list/modal update path, single prompt, selected default, confirmation, Escape, cursor and concise category return'
