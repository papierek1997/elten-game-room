require_relative "../support/game_option_encoding"
require_relative "../support/blackjack"
require_relative "../../lib/game_simulation"

GameRoomTestLocalization.use_language("pl")

def check(value, message); raise message unless value; end

blackjack = BlackjackChecksSupport::FixedDeck.new
blackjack.first_cards = %w[AS 9C 9D 6H TH 7H 2C]
repo = BlackjackChecksSupport::Repository.new(%w[Alice Bob])
session = {"options" => JSON.generate(blackjack.default_options), "__id" => 314}
deal = BlackjackChecksSupport.event(1, "Alice", "deal", "1|#{'0' * 32}")
waiting = blackjack.replay(session, [], repo)
replay = blackjack.replay(session, [deal], repo)
check(blackjack.game_shortcuts(waiting, "Alice").none? { |shortcut| shortcut.key == "space" }, "Space available during an automatic deal")
check(blackjack.game_shortcuts(replay, "Bob").none? { |shortcut| shortcut.key == "space" }, "Space available out of turn")
check(blackjack.game_shortcuts(replay, "Observer").none? { |shortcut| shortcut.key == "space" }, "Observer can draw")

layout = GameRoomLayout::Screen.new(view_spec: blackjack.game_view_spec(replay, "Alice"), chat_text: "", chat_index: 0,
  chat_check: 0, history_items: [], user_items: repo.players)
screen = GameScreen.allocate
screen.define_singleton_method(:getkeychar) { "" }
actions = []
screen.send(:bind_game_shortcuts, layout.form, layout.shortcut_fields, blackjack.game_shortcuts(replay, "Alice")) do |shortcut|
  actions << screen.send(:activate_game_shortcut, shortcut, layout.surface, replay: replay)
end
layout.form.trigger(:key_space, [false, false, false])
check(actions.one? && actions.first.to_h["action"] == "hit", "The actual Space handler did not draw a card")
check(blackjack.action_for(actions.first.to_h, replay, "Alice").first == :ok, "The game rejected Space's draw action")
check(blackjack.action_for(actions.first.to_h, replay, "Bob").first == :not_your_turn, "Space bypassed move validation")

speech = blackjack.describe_event(deal, repo, replay, "Alice")
check(speech.any? { |line| line.start_with?("Karty gracza Alice:") } &&
  speech.none? { |line| line.start_with?("Karty gracza Bob:") }, "Opening hand is missing or other hands are read over it")
hole = blackjack.send(:playing_card_label, replay.state[:dealer].last)
check(speech.none? { |line| line.include?(hole) }, "Dealer hole card was read during the deal")
draw = BlackjackChecksSupport.event(2, "Alice", "hit")
after = blackjack.replay(session, [deal, draw], repo)
check(blackjack.describe_event(draw, repo, after, "Bob").one? { |line| line.start_with?("Alice dobiera") && line.include?("Suma:") },
  "Opponent was not told which card was drawn and the new total")

class AuctionAudioRecorder
  attr_reader :assets
  def initialize; @assets = []; end
  def play_sound_from_asset(name, volume:)
    @assets << name
    nil
  end
end

def press_auction(env, action)
  picked = env.legal_actions.find { |legal| legal["action"] == action }
  check(picked && env.step(picked, actor: env.active_actor) == :ok, "Rejected #{action}")
end

def verify_auction_audio(env, actions)
  program = AuctionAudioRecorder.new
  speech = []
  presenter = GameRoomEventPresenter.new(game: -> { env.game }, repository: -> { env.repository },
    program: -> { program }, viewer: -> { "Alice" }, client: -> {}, surface_state: -> { {} },
    clock: -> { 0 }, covered: -> { false }, speech: ->(line) { speech << line }, trace: ->(*, **) {},
    history_changed: ->(*args) {}, session_changed: -> {})
  actions.each do |action, cue|
    if action == "ante"
      before = env.game.replay(env.session, [], env.repository)
      event = env.events.first
    else
      before = env.replay
      index = env.events.size
      press_auction(env, action)
      event = env.events.fetch(index)
    end
    last = env.game.replay(env.session, env.events.take_while { |candidate| candidate != event } + [event], env.repository)
    program.assets.clear
    speech.clear
    presenter.send(:present_game_event, event, before, last, last, 0, include_result: false)
    check(program.assets.include?(cue), "#{env.game.id} #{action} did not reach the shared sound output")
    check(speech.any? { |line| line.match?(/Alice|Bob|Carol/) }, "#{env.game.id} #{action} did not name the actor")
  end
end

[GameRoomGames::Blackjack.new, GameRoomGames::BlackjackDice.new, GameRoomGames::DicePoker.new].each do |game|
  options = game.new_game_options("scoring" => "chips", "starting_chips" => 100, "stake" => 5)
  build = -> { GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob Carol], options: options, seed: 421) }
  verify_auction_audio(build.call, [["ante", "poker_call"], ["check", "poker_check"],
    ["raise", "poker_raise"], ["call", "poker_call"], ["fold", "poker_fold"]])
  verify_auction_audio(build.call, [["all_in", "poker_all_in"]])
end

game = GameRoomGames::DicePoker.new
session = {"options" => JSON.generate(game.default_options.merge("round_limit" => 1))}
%w[2,3,4,5,6 1,1,1,1,1].each do |other|
  events = [%w[Alice roll 1,1,1,1,1], %w[Alice stand 1], ["Bob", "roll", other], %w[Bob stand 1]]
    .map.with_index { |args, index| BlackjackChecksSupport.event(index + 1, *args) }
  replay = game.replay(session, events, repo)
  text = replay.history.find { |entry| entry.kind == :round }.text
  if other == "1,1,1,1,1"
    check(text.include?("Remis: Alice, Bob") && replay.state[:scores].values == [1, 1], "Tie result or points are wrong")
  else
    check(text.include?("Alice wygrywa i zdobywa punkt.") && replay.state[:scores].values == [1, 0], "Single winner announced as a tie")
  end
end
puts "New game presentation: Space handler, blackjack visibility, auction effects through the shared presenter and Polish dice poker results."
