require_relative '../../support/billiards_native'
require_relative '../../../lib/game_screen'

module BilliardsVariantsNativeTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  def self.attach(match, replay)
    surface = GameSurfaces.build(match.game.surface_spec(replay, replay.current_player))
    form = GameRoomUI::Form.new(surface.fields, quiet: true)
    surface.attach_form(form)
    surface.action_guard = -> { true }
    screen = GameScreen.allocate
    GameRoomShortcutBindings.bind(form, surface.fields, match.game.game_shortcuts(replay, replay.current_player), consume: ->(_key) {}) do |shortcut|
      screen.send(:activate_game_shortcut, shortcut, surface, replay: replay)
    end
    [surface, form]
  end
  def self.choices(driver, indices)
    chooser = ->(dialog) do
      dialog.fields.first.index = indices.shift
      dialog.accept_button.trigger(:press)
      driver.dialog = chooser unless indices.empty?
    end
    driver.dialog = chooser
  end
  def self.run
    driver = BilliardsNativeDriver.new
    bank = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'bank_full'})
    replay = bank.replay
    replay.state[:breaking], replay.state[:hand] = false, nil
    surface, form = attach(bank, replay)
    choices(driver, [0, 0, 0, 2, 0, 2, 4])
    driver.frame(form, [0x50])
    driver.frame(form)
    assert_equal([0, 2], surface.state['rails'], 'P did not retain the ordered bank route')
    assert_equal(1, surface.state['call'])
    assert_equal(0, form.index, 'Declaration moved the game focus')
    previous = Marshal.dump(surface.state)
    driver.dialog = ->(dialog) { dialog.cancel_button.trigger(:press) }
    surface.handle_command('match_options')
    assert_equal(previous, Marshal.dump(surface.state), 'Cancel changed the declared route')
    actions = []
    surface.on_action { |action| actions << action }
    driver.frame(surface.fields.first, [0x20])
    driver.frame(surface.fields.first)
    assert_equal([0, 2], actions.first['rails'])
    assert_equal(:ok, bank.game.action_for(actions.first, replay, 'Alice').first)

    ten = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'ten'})
    replay = ten.replay
    replay.state[:breaking], replay.state[:hand], replay.state[:push_available] = false, nil, true
    surface, = attach(ten, replay)
    choices(driver, [0, 1])
    surface.handle_command('match_options')
    assert_equal(2, surface.state['mode'], 'Ten-ball P did not allow a push-out')

    english = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'english'})
    replay = english.replay
    replay.state[:turn] = 1
    replay.state[:balls].first.x = 1.4
    replay.current_player = 'Bob'
    surface, = attach(english, replay)
    actions = []
    surface.on_action { |action| actions << action }
    driver.dialog = ->(dialog) do
      dialog.fields[0].set_text('55')
      dialog.fields[1].set_text((B::Rules.table(replay.state[:options]).height * 50).to_s)
      dialog.accept_button.trigger(:press)
    end
    surface.handle_command('place')
    assert_equal(1, actions.first['ball'], 'M moved the other player\'s cue ball')
    assert_equal(:ok, english.game.action_for(actions.first, replay, 'Bob').first)

    pyramid = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'pyramid'})
    replay = pyramid.replay
    replay.state[:breaking], replay.state[:hand] = false, nil
    replay.state[:balls] = [B::Ball.new(id: 0, x: 1.4, y: 0.8), B::Ball.new(id: 1, x: 0.8, y: 0.8)]
    surface, form = attach(pyramid, replay)
    choices(driver, [2, 1])
    surface.handle_command('match_options')
    assert_equal(1, surface.state['cue'])
    assert_equal(0, form.index)
    surface.on_action { raise 'A prediction wrote a move' }
    SpeechOutput.reset
    driver.frame(form, [0xbc])
    driver.frame(form)
    assert(SpeechOutput.calls.last.first.start_with?('Ball 0, coloured:'), 'Comma ignored the selected Pyramid cue')
    assert_equal(0, form.index)
    assert_equal([], pyramid.events)
    puts 'New billiards native controls: P bank route and cancellation, Space with wire3, ten-ball push-out, M for the second English cue, Pyramid cue selection and spoken comma prediction passed.'
  end
end
BilliardsVariantsNativeTest.run if $PROGRAM_NAME == __FILE__
