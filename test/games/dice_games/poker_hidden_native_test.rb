require_relative "../../support/host_source"
require_relative "../../support/duck_challenge_native"
require_relative "../../support/localization"
require_relative "../../support/dice_games"
require_relative "../../../lib/game_screen"
include DiceGamesSupport

def poker_controls(game, replay, viewer)
  Session.name = viewer
  driver = DuckChallengeNativeDriver.new
  layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay, viewer),
    history_items: replay.history.map(&:text), user_items: replay.players)
  actions = []
  layout.surface.on_action { |action| actions << action }
  screen = GameScreen.allocate
  screen.instance_variable_set(:@game, game)
  GameRoomShortcutBindings.bind(layout.form, layout.shortcut_fields, game.game_shortcuts(replay, viewer),
    consume: ->(*) { EltenAPI::KeyboardState.clear_current_frame }) do |shortcut|
    result = screen.send(:activate_game_shortcut, shortcut, layout.surface, replay: replay)
    actions << result if result.is_a?(GameSurfaces::Action)
  end
  layout.form.index = layout.form.fields.index(layout.surface.fields.first)
  SpeechOutput.reset
  layout.form.focus
  [driver, layout, actions]
end

game = GameRoomGames::DicePoker.new
repo = Repository.new(%w[Alice Bob])
session = dice_session(game, scoring: "chips", round_limit: 1)
moves = [["Alice", "ante", "1"], ["Alice", "roll", "1,1,2,3,4"], ["Alice", "stand", "1"],
  ["Bob", "roll", "6,6,6,6,6"], ["Bob", "stand", "1"]]
events = moves.each_with_index.map { |args, i| dice_event(i + 1, *args) }
before = game.replay(session, events.take(1), repo)
rolled = game.replay(session, events.take(2), repo)
betting = game.replay(session, events, repo)
context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(2), server_random: true)

%w[en pl cs es ru].each do |language|
  GameRoomTestLocalization.use_language(language)
  announced = game.replay(session, events, repo)
  expected = {
    'en'=>'All hands are set. Betting begins.',
    'pl'=>'Wszyscy wybrali układy. Czas na licytację.',
    'cs'=>'Všichni si ponechali svou kombinaci. Začíná sázení.',
    'es'=>'Todos han elegido su combinación. Empiezan las apuestas.',
    'ru'=>'Все выбрали комбинации. Начинаются ставки.'
  }.fetch(language)
  assert(game.describe_event(events.last, repo, announced, 'Alice').count(expected) == 1,
    "#{language}: betting announcement is missing, repeated or still says second betting round")
  driver, layout, actions = poker_controls(game, before, "Alice")
  driver.frame(layout.form)
  driver.frame(layout.form, driver.tap(0x0D))
  assert(actions.size == 1 && actions.first.name == "roll", "#{language}: first Enter does not roll after ante")
  status, plan = game.action_for(actions.last, before, "Alice", context: context)
  assert(status == :ok && plan.events.first.random_request.fetch("count") == 5, "First Enter bypasses the ordinary native dice path")

  driver, layout, actions = poker_controls(game, rolled, "Alice")
  driver.frame(layout.form)
  SpeechOutput.reset
  driver.frame(layout.form, driver.tap(0x20), characters: " ")
  assert(actions.empty? && !SpeechOutput.calls.empty?, "#{language}: Space does not read own dice or writes a roll")
  driver.frame(layout.form)
  driver.frame(layout.form, driver.tap(0x4B), characters: "k")
  assert(actions.size == 1 && game.action_for(actions.last, rolled, "Alice").first == :ok, "K does not keep the hand through validation")

  driver, layout, actions = poker_controls(game, betting, "Alice")
  assert(layout.surface.fields.size == 1, "Betting adds another game field")
  driver.frame(layout.form)
  SpeechOutput.reset
  driver.frame(layout.form, driver.tap(0x48), characters: "h")
  own = game.game_shortcuts(betting, "Alice").find { |key| key.key == "h" }.message
  assert(SpeechOutput.calls.map(&:first) == [own] && actions.empty?, "#{language}: H duplicates, leaks another hand or writes a bet")
  assert(language == "en" || !own.start_with?("Your dice:"), "Own-hand shortcut is untranslated")
  layout.form.index = layout.form.fields.index(layout.chat)
  driver.frame(layout.form)
  SpeechOutput.reset
  driver.frame(layout.form, driver.tap(0x48), characters: "h")
  assert(SpeechOutput.calls.map(&:first).none? { |line| line == own }, "H steals text input outside the game field")
  layout.form.index = layout.form.fields.index(layout.surface.fields.first)
  driver.frame(layout.form)
  driver.frame(layout.form, driver.tap(0x43), characters: "c")
  assert(actions.one? && game.action_for(actions.last, betting, "Alice").first == :ok, "C does not check through the shared auction")
  assert(game.action_for(actions.last, betting, "Bob").first == :not_your_turn, "Bet shortcut bypasses turn validation")

  %w[Bob Observer].each do |viewer|
    driver, layout, actions = poker_controls(game, rolled, viewer)
    driver.frame(layout.form)
    SpeechOutput.reset
    driver.frame(layout.form, driver.tap(0x48), characters: "h")
    driver.frame(layout.form)
    driver.frame(layout.form, driver.tap(0x20), characters: " ")
    # The native status list may repeat its public row on a search/Space.
    status = game.current_turn_shortcut_text(rolled, viewer)
    assert(actions.empty? && SpeechOutput.calls.all? { |line, *| line == status }, "Waiting keys reveal more than the public turn status")
  end
end
puts "PASS Dice Poker native Enter/Space/K/H/C, ante-to-roll flow, own-hand speech once, chat gating and waiting/spectator privacy in five languages"
