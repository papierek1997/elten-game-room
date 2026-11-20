require_relative '../support/duck_challenge_native'
require_relative '../support/cat_head_tail'
require_relative '../support/localization'
require_relative '../../games/kosciane'
require_relative '../../games/balut'

%w[en pl cs es ru].each do |language|
  GameRoomTestLocalization.use_language(language)
  [GameRoomGames::Kosciane.new, GameRoomGames::Balut.new].each do |game|
    repository = CatHeadTailRepository.new(%w[Alice Bob])
    session = {'options'=>JSON.generate(game.default_options)}
    events = 3.times.map { |index| cht_event(index+1, 'Alice', 'roll', '2,2,5,5,5') }
    replay = game.replay(session, events, repository)
    [true, false].each do |writable|
      grid = game.send(:score_grid, replay.state, 'Alice', writable: writable)
      surface = GameSurfaces.build(grid)
      driver = DuckChallengeNativeDriver.new
      form = driver.form(surface)
      selections = []
      surface.on_action { |action| selections << action }
      SpeechOutput.reset
      driver.frame(form, driver.tap(0x26))
      expected = grid.cells.first.first
      assert(SpeechOutput.calls.map(&:first) == [expected],
        "#{language}/#{game.id}/#{writable}: Up at the first row must read that row once without the table header")
      assert(surface.state.values_at('x', 'y') == [0, 0] && selections.empty?, 'Boundary readout moves or submits a result')
      driver.frame(form)
      SpeechOutput.reset
      driver.frame(form, driver.tap(0x28))
      assert(SpeechOutput.calls.map(&:first) == [grid.cells[1].first], 'Ordinary table movement changed or duplicates speech')
    end
  end
end

# Real board grids do not acquire a table-only boundary readout.
grid = GameSurfaces::GridSpec.new(width: 2, height: 2, cells: [%w[A B], %w[C D]], row_origin: :top)
surface = GameSurfaces.build(grid)
driver = DuckChallengeNativeDriver.new
form = driver.form(surface)
SpeechOutput.reset
driver.frame(form, driver.tap(0x26))
assert(SpeechOutput.calls.empty?, 'An ordinary board gained score-table boundary speech')
puts 'PASS native table boundary: top Up reads once without header/action, regular movement unchanged, five languages, writable/read-only tables and board isolation'
