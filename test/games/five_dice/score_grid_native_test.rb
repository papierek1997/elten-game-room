require_relative '../../support/typing_native_form'

NativeOptionTest.language = 'en'
Session.name = 'Alice'

class FiveDiceModalDriver < NativeOptionTest::Driver
  attr_reader :root, :result, :chat

  def initialize(game, replay, gate: nil)
    @raw_keys, @frames = [], 0
    @program = NativeOptionTest::Program.new
    @game = game
    NativeOptionUI.driver = self
    @fiber = Fiber.new do
      play = Button.new('Game')
      @chat = EditBox.new('Chat', text: 'Unsent draft', quiet: true)
      if gate
        layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay,'Alice'), history_items:[], user_items:[], users_header:'Users')
        @root, @chat = layout.form, layout.chat
        chat.set_text('Unsent draft')
      else
        @root = GameRoomUI::Form.new([play, chat], program: @program, quiet: true)
        root.extend(GameRoomLayout::ShortcutFormBehavior)
      end
      screen = GameScreen.allocate
      screen.instance_variable_set(:@program, program)
      screen.instance_variable_set(:@game, game)
      screen.instance_variable_set(:@session, {'__frozen' => gate==:frozen})
      screen.instance_variable_set(:@layout, layout || Struct.new(:form).new(root))
      if gate
        screen.define_singleton_method(:event_presentation_busy?) { gate==:busy }
        activate=screen.method(:activate_game_shortcut)
        driver=self
        screen.define_singleton_method(:activate_game_shortcut) do |*args, **kwargs|
          result=activate.call(*args,**kwargs)
          driver.instance_variable_set(:@result,result)
          nil # This fixture observes local inspection, not a server submission.
        end
        wait=GameScreen::WaitState.new(replay:replay,session:{},actor:'Alice')
        screen.send(:bind_wait_shortcuts,wait,layout,-> {})
      else
        shortcut = game.game_shortcuts(replay, 'Alice').find { |entry| entry.key == 'b' }
        screen.send(:bind_game_shortcuts, root, [play], [shortcut]) do |entry|
          @result = screen.send(:activate_game_shortcut, entry, replay: replay)
        end
      end
      root.wait
    end
    @form = @fiber.resume
  end

  def press(keys, characters = '')
    outcome = @fiber.resume([keys, characters])
    @form = outcome if @fiber.alive?
    if @fiber.alive?
      outcome = @fiber.resume([[], ''])
      @form = outcome if @fiber.alive?
    end
  end

  def close
    root.resume
    @fiber.resume([[], '']) if @fiber.alive?
    raise 'Parent form leaked' if @fiber.alive?
  end
end

[GameRoomGames::Balut.new, GameRoomGames::Kosciane.new].each do |game|
  players = %w[Alice Bob]
  if game.id == 'balut'
    sheet = GameRoomGames::BalutScoring::CATEGORIES.to_h { |category| [category, []] }
    state = {players: players, current_player: 'Alice', turn_rolls: 1, dice: [2, 2, 3, 4, 5],
      sheets: players.to_h { |player| [player, sheet.transform_values(&:dup)] }}
  else
    match = GameRoomGames::FiveDiceMatch.new(players)
    match.roll('Alice', (0...5).to_a, [2, 2, 3, 4, 5])
    state = {players: players, current_player: 'Alice', turn_rolls: 1, dice: match.dice,
      match_model: match, options: game.default_options}
  end
  replay = GameRoomGames::Replay.new(players: players, current_player: 'Alice', state: state)
  driver = FiveDiceModalDriver.new(game, replay)
  begin
    NativeOptionUI.spoken.clear
    driver.press([66], 'b')
    raise 'B did not open the native grid' if driver.form.equal?(driver.root)
    prompts = NativeOptionUI.spoken.count { |text| text.include?('Score sheet: Alice') }
    raise "Grid prompt was spoken #{prompts} times" unless prompts == 1
    driver.press([40])
    driver.press([39])
    raise 'Grid navigation repeated its header' unless NativeOptionUI.spoken.count { |text| text.include?('Score sheet: Alice') } == 1
    driver.press([32], ' ')
    raise "Space lost the game-owned dice readout: #{NativeOptionUI.spoken.last(6).inspect}" unless NativeOptionUI.spoken.last == '2, 2, 3, 4, 5.'
    driver.press([27])
    raise 'Escape submitted or lost the parent' unless driver.form.equal?(driver.root) && driver.result.nil?
    raise 'Modal changed chat/focus' unless driver.chat.text == 'Unsent draft' && driver.root.index == 0
    driver.press([66], 'b')
    driver.press([13])
    raise 'Enter did not return a score action' unless driver.form.equal?(driver.root) && driver.result['action'] == 'score'
    raise 'Closing Enter activated the parent' unless driver.root.index == 0 && driver.chat.text == 'Unsent draft'
  ensure
    driver.close
  end
  [:frozen,:busy].each do |gate|
    guarded = FiveDiceModalDriver.new(game,replay,gate:gate)
    begin
      guarded.press([66],'b')
      raise "#{gate}: safe score inspection was blocked" if guarded.form.equal?(guarded.root)
      guarded.press([13])
      raise "#{gate}: inspecting a guarded sheet created an action" if guarded.form.equal?(guarded.root) || guarded.result
      guarded.press([27])
      raise "#{gate}: inspection changed the draft or parent" unless guarded.form.equal?(guarded.root) && guarded.chat.text=='Unsent draft'
    ensure
      guarded.close
    end
  end
end
puts 'PASS native score grids: actual B, one prompt, navigation/readout, Escape, Enter, preserved parent focus and chat'
