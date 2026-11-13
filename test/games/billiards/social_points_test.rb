require_relative '../../support/billiards_rules'
require_relative '../../support/billiards_native'
require_relative '../../../lib/game_screen'

module BilliardsSocialPointsTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  F = BilliardsRulesFixture
  def self.run
    game = GameRoomGames::Billiards.new
    assert_equal('friendly', game.table_creation_options['discipline'])
    assert_equal('diamond', game.table_creation_options['layout'])
    %w[single diamond triangle].each do |layout|
      assert_equal(layout, game.table_creation_options('layout'=>layout)['layout'], 'An explicit layout changed')
      assert_equal(layout, game.table_creation_options(layout: layout)['layout'], 'A symbol-keyed layout changed')
    end
    assert_equal('friendly', game.option_definitions.find { |definition| definition.key == 'discipline' }.default)
    assert_equal('eight', game.table_creation_options('discipline'=>'eight')['discipline'])
    assert_equal('practice', game.normalize_options({})['discipline'], 'A new default changed old practice saves')
    assert_equal('single', game.normalize_options({})['layout'], 'A new default changed old practice balls')
    assert_equal('single', game.normalize_options('discipline'=>'friendly')['layout'], 'A new default changed an existing social table')
    default_match = BilliardsFixture::Match.new(players: %w[Alice Bob], options: game.table_creation_options)
    assert_equal((0..9).to_a, default_match.replay.state[:balls].map(&:id).sort)
    assert_equal(9, default_match.replay.state[:final_ball])
    state = F.state('friendly')
    state[:options].merge!('layout'=>'triangle', 'rounds'=>2)
    B::Rules.setup(state)
    F.apply(state, F.result(state, first: 1, pots: [[1, 0], [2, 1]]), call: 0)
    assert_equal([2, 0], state[:scores])
    assert_equal([0, 0], state[:racks])
    F.apply(state, F.result(state, first: 3, pots: [[3, 0], [0, 1]]), call: 0)
    assert_equal([2, 0], state[:scores], 'A scratch earned pot points')
    state[:balls].first.status = :table
    state[:hand] = nil
    state[:balls].each { |ball| ball.status = :potted if ball.id.between?(1, 14) }
    F.apply(state, F.result(state, first: 15, pots: [[15, 0]]), call: 0)
    assert_equal([2, 1], state[:scores], 'The legal final ball did not earn one point')
    assert_equal([0, 1], state[:racks])
    B::Rules.choose(state, 'next')
    assert_equal([2, 1], state[:scores], 'The next round discarded accumulated pot points')
    B::Rules.concede(state)
    assert_equal([1, 1], state[:racks])
    assert_equal([2, 1], state[:scores], 'Conceding or winning without a pot invented a pot point')
    assert_equal(nil, state[:winner], 'Pot points broke a tie in won rounds')
    early = F.state('friendly')
    early[:options].merge!('layout'=>'triangle', 'rounds'=>1)
    B::Rules.setup(early)
    F.apply(early, F.result(early, first: 1, pots: [[1, 0], [15, 1]]), call: 0)
    assert_equal([0, 0], early[:scores], 'An early final-ball loss earned pot points')
    check_replay_and_speech
    puts 'Social billiards: new-table default, preserved explicit/legacy variants, legal pot points, final ball, foul/early/concession, cumulative rounds, unchanged match ties, cold replay and native spoken S passed.'
  end

  def self.check_replay_and_speech
    match = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'friendly', 'rounds'=>2})
    8.times do
      replay = match.replay
      move = match.game.bot_strategy.choose(actions: match.game.legal_actions(replay, replay.current_player), replay: replay)
      match.submit(move['action'], move.reject { |key, _| %w[kind action revision].include?(key) })
      break if match.replay.state[:phase] == :rack_end
    end
    replay = match.replay
    assert_equal(1, replay.state[:scores].sum, 'The real final-ball fixture did not score')
    assert_equal(1, replay.state[:racks].sum)
    assert_equal(replay, GameRoomGames::Billiards.new.replay(match.session, match.events, match.repository))
    driver = BilliardsNativeDriver.new
    surface = GameSurfaces.build(match.game.surface_spec(replay, replay.current_player))
    form = GameRoomUI::Form.new(surface.fields, quiet: true)
    surface.attach_form(form)
    surface.action_guard = -> { true }
    surface.on_action { raise 'S wrote a move' }
    screen = GameScreen.allocate
    GameRoomShortcutBindings.bind(form, surface.fields, match.game.game_shortcuts(replay, replay.current_player), consume: ->(_key) {}) do |shortcut|
      screen.send(:activate_game_shortcut, shortcut, surface, replay: replay)
    end
    SpeechOutput.reset
    driver.frame(form, [0x53]); driver.frame(form)
    spoken = SpeechOutput.calls.last.first
    assert(spoken.include?('rounds won:') && spoken.include?('Points: 1') && spoken.include?('Points: 0'))
    assert_equal(0, form.index, 'S moved focus or opened another control')
  end
end
BilliardsSocialPointsTest.run if $PROGRAM_NAME == __FILE__
