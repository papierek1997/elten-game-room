require_relative '../../support/billiards_native'
require_relative '../../../lib/game_screen'

module BilliardsCompetitionNativeTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  def self.attach(match, replay = match.replay)
    surface = GameSurfaces.build(match.game.surface_spec(replay, replay.current_player))
    form = GameRoomUI::Form.new(surface.fields, quiet: true)
    surface.attach_form(form)
    surface.action_guard = -> { true }
    [surface, form]
  end
  def self.run
    driver = BilliardsNativeDriver.new
    match = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'eight'})
    replay = match.replay
    replay.state[:breaking], replay.state[:hand] = false, nil
    surface, form = attach(match, replay)
    actions = []
    surface.on_action { |a| actions << a }
    queue = [0, 0, 4]
    chooser = ->(dialog) do
      dialog.fields.first.index = queue.shift
      dialog.accept_button.trigger(:press)
      driver.dialog = chooser unless queue.empty?
    end
    driver.dialog = chooser
    driver.frame(surface.fields.first, [0x20])
    driver.frame(surface.fields.first)
    assert_equal(1, actions.length)
    assert_equal([1, 4, 0], actions.first.to_h.values_at('call', 'pocket', 'mode'))
    assert_equal(:ok, match.game.action_for(actions.first, replay, 'Alice').first)
    assert_equal(false, surface.handle_command('reset'), 'Competition exposed a practice reset')
    assert_equal(false, surface.handle_command('undo'), 'Competition exposed practice undo')
    shortcuts = match.game.game_shortcuts(replay, 'Alice')
    assert(shortcuts.any? { |s| s.key == 'p' && s.kind == :surface })
    assert(!shortcuts.any? { |s| s.key == 'r' && s.modifiers.to_a.include?(:shift) })
    assert_equal(shortcuts.size, shortcuts.map { |s| [s.key, s.modifiers.to_a] }.uniq.size, 'Competition shortcut conflict')

    scratch = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'nine'})
    scratch.submit('place', {'ball'=>0, 'x'=>300, 'y'=>300})
    replay = scratch.submit('shot', {'shot'=>scratch.shot.merge('angle'=>22500), 'call'=>0, 'pocket'=>0, 'mode'=>0})
    objects = Marshal.dump(replay.state[:balls].drop(1))
    surface, = attach(scratch, replay)
    placed = []
    surface.on_action { |a| placed << a }
    driver.dialog = ->(dialog) do
      assert(dialog.fields.first.is_a?(EditBox), 'Scratch asked the player to select an object ball')
      dialog.fields[0].set_text('50')
      dialog.fields[1].set_text('50')
      dialog.accept_button.trigger(:press)
    end
    surface.handle_command('place')
    assert_equal([0, 5000, 5000], placed.first.to_h.values_at('ball', 'x', 'y'))
    assert_equal(:ok, scratch.game.action_for(placed.first, replay, 'Bob').first)
    assert_equal(objects, Marshal.dump(replay.state[:balls].drop(1)))

    snooker = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'snooker'})
    replay = snooker.replay
    replay.state[:on], replay.state[:hand], replay.state[:breaking] = :colour, nil, false
    surface, = attach(snooker, replay)
    declared = []
    surface.on_action { |a| declared << a }
    driver.dialog = ->(dialog) { dialog.fields.first.index = 5; dialog.accept_button.trigger(:press) }
    surface.send(:submit, 'shot', 'shot'=>snooker.shot)
    assert_equal(21, declared.first['call'])
    assert_equal(:ok, snooker.game.action_for(declared.first, replay, 'Alice').first)
    assert_equal('Ball 8, red', B::Presentation.ball(8, discipline: 'snooker'))
    assert_equal('Ball 21, black', B::Presentation.ball(21, discipline: 'snooker'))
    score = snooker.game.game_shortcuts(replay, 'Alice').find { |s| s.key == 's' }
    assert_equal(:announcement, score.kind)
    assert(score.message.include?('Points: 0'))
    old = surface.state
    driver.dialog = ->(dialog) { dialog.cancel_button.trigger(:press) }
    surface.handle_command('match_options')
    assert_equal(old, surface.state, 'Cancelled declaration altered the draft')
    puts 'Competitive billiards native controls: Space declares ball/pocket, competition-only bindings, white-only scratch form, snooker colours, spoken S and modal cancellation passed.'
  end
end
BilliardsCompetitionNativeTest.run if $PROGRAM_NAME == __FILE__
