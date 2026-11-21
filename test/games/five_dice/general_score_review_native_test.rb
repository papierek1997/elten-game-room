require_relative '../../support/typing_native_form'
require_relative '../../support/cat_head_tail'
require_relative '../../../games/kosciane'

NativeOptionTest.language = 'en'

def general_position(players, strict_school: true, columns: 3)
  game = GameRoomGames::Kosciane.new
  session = {'options' => JSON.generate(game.default_options.merge('strict_school' => strict_school, 'columns' => columns))}
  repo = CatHeadTailRepository.new(players)
  events = []
  append = ->(actor, action, value) { events << cht_event(events.length + 1, actor, action, value) }
  if columns == 3
    columns.times do
      players.each_with_index do |player, index|
        append.call(player, 'roll', Array.new(5, 6 - index).join(','))
        append.call(player, 'score', index.zero? ? 'chance' : 'pair')
      end
    end
  end
  3.times { append.call('Alice', 'roll', '6,6,6,6,6') }
  [game, game.replay(session, events, repo), repo, session, events]
end

class GeneralReviewDriver < NativeOptionTest::Driver
  attr_reader :root, :actions, :chat

  def initialize(game, replay, user:, writable: false)
    Session.name = user
    @raw_keys, @frames, @actions = [], 0, []
    @program = NativeOptionTest::Program.new
    NativeOptionUI.driver = self
    @fiber = Fiber.new do
      layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay, user),
        user_items: replay.players, chat_text: 'Unsent draft', focus_location: [:game, 0])
      @root, @chat = layout.form, layout.chat
      screen = GameScreen.allocate
      screen.instance_variable_set(:@program, program)
      screen.instance_variable_set(:@game, game)
      screen.instance_variable_set(:@table_owner, 'Alice')
      screen.instance_variable_set(:@session, {})
      screen.define_singleton_method(:event_presentation_busy?) { false }
      if writable
        screen.instance_variable_set(:@session_runner, Object.new)
        screen.instance_variable_set(:@repository, Struct.new(:x) { def event_id(event); event['id']; end }.new)
        actions = @actions
        screen.define_singleton_method(:submit_runner_action) do |current, selection, actor, **|
          status, plan = game.action_for(selection, current, actor)
          raise "Illegal score sent: #{status}" unless status == :ok
          actions.concat(plan.events)
          [{'id' => 1}]
        end
      end
      screen.send(:bind_game_shortcuts, root, layout.shortcut_fields, game.game_shortcuts(replay, user)) do |shortcut|
        selection = screen.send(:activate_game_shortcut, shortcut, replay: replay)
        if selection
          screen.instance_variable_set(:@selected_surface_action, selection)
          screen.send(:submit_action, replay)
        end
      end
      root.wait
    end
    @form = @fiber.resume
  end

  def press(keys, characters = '')
    @form = @fiber.resume([keys, characters])
    @form = @fiber.resume([[], '']) if @fiber.alive?
  end

  def list
    form.fields.first
  end

  def close
    root.resume
    @fiber.resume([[], '']) if @fiber.alive?
    raise 'The native score viewer leaked its parent' if @fiber.alive?
  end
end

game, replay, repo, session, events = general_position(%w[Alice Bob])
assert(replay.state[:match_model].bonuses('Alice') == {[:row, :chance] => 30}, 'Fixture did not earn a row bonus')
driver = GeneralReviewDriver.new(game, replay, user: 'Alice', writable: true)
begin
  driver.press([70], 'f')
  list = driver.list
  assert(list.header == 'Unfilled categories' && list.options.none? { |row| row.start_with?('Chance:') },
    'F did not open the unfilled list')
  driver.press([40])
  index = list.index
  NativeOptionUI.spoken.clear
  driver.press([39])
  assert(driver.list.equal?(list) && list.header == 'Completed categories' && list.options == ['Chance: 30, 30, 30; Bonus: 30'],
    'Right did not show the completed row and its actual bonus in the same list')
  assert(NativeOptionUI.spoken.count { |line| line.include?('Completed categories') } == 1, 'Page change repeated its title')
  driver.press([37])
  assert(list.header == 'Unfilled categories' && list.index == index, 'Left did not restore the unfilled cursor')
  driver.press([27])

  driver.press([16,70], 'F')
  assert(driver.list.header == 'Score sheet: Bob. Unfilled categories', 'A single opponent still needs a chooser')
  driver.press([39])
  assert(driver.list.options == ['One pair: 10, 10, 10; Bonus: 10'], 'Shift+F showed the wrong opponent or bonus')
  driver.press([27])

  %i[escape no yes].each do |answer|
    driver.press([66], 'b')
    NativeOptionUI.spoken.clear
    driver.press([13])
    assert(driver.list.options == ['No', 'Yes'] && driver.list.index == 0, 'Zero was selected without a default-safe confirmation')
    assert(driver.list.header == 'Record zero for Ones? You will lose your bonuses (30 points). You will not be able to earn any more bonuses in this game.',
      'Confirmation did not explain the actual cost and strict-school consequence')
    assert(driver.actions.empty?, 'Zero was already sent before confirmation')
    driver.press([40]) if answer == :yes
    driver.press(answer == :escape ? [27] : [13])
    assert(driver.form.equal?(driver.root) && driver.chat.text == 'Unsent draft', 'Confirmation lost the parent or chat draft')
    assert(driver.actions.empty? == (answer != :yes), 'Only Yes may write the score')
  end
  action = driver.actions.fetch(0)
  assert(driver.actions.one? && action.action == 'score' && action.value == 'cross:1', 'Yes did not submit exactly one school zero')
  updated = game.replay(session, events + [cht_event(events.length + 1, 'Alice', action.action, action.value)], repo)
  assert(updated.state[:match_model].bonuses('Alice').empty?, 'The confirmed action did not remove the earned bonus')
  grid = game.score_grid(replay.state, 'Alice', writable: false)
  chance = grid.cells.find { |row| row.first == 'Chance' }
  assert(chance.include?('Bonus: 30') && grid.cells.last.include?('Bonuses: 30'), 'The two-dimensional sheet is missing the earned bonus')
ensure
  driver.close
end

game, replay = general_position(%w[Alice Bob Carol])
{'Alice' => %w[Bob Carol], 'Watcher' => %w[Alice Bob Carol]}.each do |user, names|
  driver = GeneralReviewDriver.new(game, replay, user: user)
  begin
    driver.press([16,70], 'F')
    chooser = driver.list
    assert(chooser.options == names, "#{user}: wrong participants in Shift+F")
    driver.press([40])
    driver.press([13])
    assert(driver.list.header == "Score sheet: #{names.fetch(1)}. Unfilled categories", 'The chosen player did not open')
    driver.press([39])
    assert(driver.list.header.end_with?('. Completed categories'), 'An opponent chosen in a list lost its second page')
    driver.press([27])
    assert(driver.list.equal?(chooser) && chooser.index == 1, 'Escape lost the participant chooser or its selection')
    driver.press([27])
  ensure
    driver.close
  end
end

variants = [
  [false, 3, 'Record zero for Ones? You will lose your bonuses (30 points).'],
  [true, 1, 'Record zero for Ones?']
]
variants.each do |strict, columns, text|
  game, replay = general_position(%w[Alice Bob], strict_school: strict, columns: columns)
  score = ->(category) { {'kind'=>'dice', 'action'=>'score', 'category'=>category} }
  assert(game.action_confirmation(score.call('cross:1'), replay, 'Alice') == text, 'A variant announced consequences it does not have')
  assert(game.action_confirmation(score.call('cross:1'), replay, 'Bob').nil? &&
    game.action_confirmation(score.call('cross:two_pairs'), replay, 'Alice').nil? &&
    game.action_confirmation(score.call('6'), replay, 'Alice').nil?, 'An unrelated score requires confirmation')
end
puts 'PASS native General F/Shift+F, both lists, spectator and opponent choice, earned bonus, and default-safe confirmation before a school zero'
