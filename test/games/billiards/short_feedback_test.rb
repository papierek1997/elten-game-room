require_relative '../../support/billiards_native'
require_relative '../../../lib/game_screen'

module BilliardsShortFeedbackTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  def self.run
    table = B::Table.new
    balls = [[0,0.3,0.4], [8,0.7,0.4], [2,1.1,0.4], [9,1.7,0.4], [3,1.0,0.7], [4,0.1,0.4]].map do |id,x,y|
      B::Ball.new(id: id,x: x,y: y)
    end
    before = Marshal.dump(balls)
    contacts = B::Geometry.through(table, balls, 0, 0)
    assert_equal([[:ball,8],[:ball,2],[:ball,9],[:rail,:right]], contacts.map { |c| c.values_at(:kind,:id) })
    assert_equal(before, Marshal.dump(balls), 'B modified the position')
    text = B::Presentation.behind(contacts)
    assert(text.start_with?('Ball 8, black; further: Ball 2, blue; Ball 9, yellow, striped; right cushion'))
    assert(!text.include?('Ball 3') && !text.include?('Ball 4'), 'B included an off-axis or rearward ball')
    assert_equal('Ball 8, black, centre.', B::Presentation.target(contacts.first))
    assert_equal('left cushion', B::Presentation.target({kind: :rail,id: :left,distance: 1}))
    assert_equal('Pocket 2, lower middle', B::Presentation.target({kind: :pocket,id: 1,distance: 1}))
    assert_equal('right cushion', B::Presentation.behind([{kind: :rail,id: :right}]))
    assert_equal([], B::Geometry.through(table, balls.reject { |b| b.id == 0 }, 0, 0))
    balls[0].x, balls[0].y = 1.27, 0.4
    balls[1].x, balls[1].y = 1.27, 0.8
    assert_equal([[:ball,8],[:pocket,4]], B::Geometry.through(table, balls, 0, 90).map { |c| c.values_at(:kind,:id) })

    driver, match = BilliardsNativeDriver.new, BilliardsFixture::Match.new(players: ['Alice','Bob'])
    replay = match.replay
    surface = GameSurfaces.build(match.game.surface_spec(replay, 'Alice'))
    surface.on_action { raise 'Readout wrote a game action' }
    form = GameRoomUI::Form.new(surface.fields, quiet: true)
    surface.attach_form(form)
    screen = GameScreen.allocate
    screen.define_singleton_method(:browse_shortcut_choices) { |_shortcut| raise 'S opened a results window' }
    GameRoomShortcutBindings.bind(form, surface.fields, match.game.game_shortcuts(replay, 'Alice'), consume: ->(_key) {}) do |shortcut|
      screen.send(:activate_game_shortcut, shortcut, surface, replay: replay)
    end
    SpeechOutput.reset
    driver.frame(form, [0x53])
    driver.frame(form)
    assert_equal('Alice; points: 0; Bob; points: 0', SpeechOutput.calls.last.first)
    assert_equal(0, form.index, 'S moved keyboard focus')
    driver.frame(form, [0x42])
    driver.frame(form)
    assert(SpeechOutput.calls.last.first.start_with?('Ball 1, yellow; further: right cushion'))
    assert_equal(0, surface.state['shot']['top'], 'B still changed draw spin')
    driver.frame(form, [0x10,0x42])
    driver.frame(form)
    assert_equal(-5, surface.state['shot']['top'], 'Shift+B did not retain draw spin')
    assert_equal([], match.events)
    puts 'Billiards concise feedback: ball/rail/pocket names, ordered B continuation to cushion/pocket, excluded rear/off-axis balls, real native S/B/Shift+B bindings, no modal/focus change or writes passed.'
  end
end
BilliardsShortFeedbackTest.run if $PROGRAM_NAME == __FILE__
