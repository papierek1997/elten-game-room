# Definition-only: the same checks can run inside ELTEN through program_eval.
require_relative "../../../games/blackjack_dice" unless defined?(GameRoomGames::BlackjackDice)
require_relative "../../../lib/game_random" unless defined?(GameRoomRandom::Source)
module BlackjackDiceChecks
  Repository = Struct.new(:players) do
    def players_for(_session); players; end
    def actor_of(event, _session = nil); event.fetch("actor"); end
    def event_id(event); event.fetch("id"); end
  end

  def self.run!
    game = GameRoomGames::BlackjackDice.new
    repo = Repository.new(%w[Alice Bob])
    session = {"options" => JSON.generate(game.default_options.merge("score_limit" => 2))}
    event = ->(id, actor, action, value = "") { {"id" => id, "actor" => actor, "action" => action, "value" => value} }
    check = ->(condition, message) { raise message unless condition }
    events = [event.call(1, "Alice", "roll", "6,6"), event.call(2, "Alice", "roll", "2,2")]
    replay = game.replay(session, events, repo)
    check.call(replay.state[:total] == 16 && game.dice_count(replay.state) == 1, "Two-to-one dice threshold")
    malformed = game.replay(session, events + [event.call(3, "Alice", "roll", "1,1")], repo)
    check.call(malformed.accepted_events.size == 2, "Wrong dice count accepted")
    events += [event.call(3, "Alice", "roll", "5"), event.call(4, "Bob", "roll", "6,6"), event.call(5, "Bob", "stand")]
    won = game.replay(session, events, repo)
    check.call(won.finished? && won.winner == "Alice" && won.state[:scores]["Alice"] == 2, "Exact 21 scoring")
    check.call(game.action_for({"action" => "roll"}, won, "Alice").first == :finished, "Post-finish move accepted")
    tied = [event.call(1, "Alice", "roll", "6,6"), event.call(2, "Alice", "stand"), event.call(3, "Bob", "roll", "6,6"), event.call(4, "Bob", "stand")]
    replay = game.replay(session, tied, repo)
    check.call(replay.state[:scores].values == [0, 0] && replay.current_player == "Bob", "Tie or rotating first seat")
    check.call(game.replay(session, tied + [tied.last], repo).accepted_events.size == 4, "Duplicate event accepted")
    single = {"options" => JSON.generate(game.default_options.merge("variant" => "one_die"))}
    replay = game.replay(single, [event.call(1, "Alice", "roll", "6")], repo)
    check.call(replay.state[:total] == 6 && game.dice_count(replay.state) == 1, "One-die variant")
    check.call(game.action_for({"action" => "stand"}, replay, "Bob").first == :not_your_turn, "Wrong actor accepted")
    check.call(game.validation_error({"score_limit" => 0}) != nil, "Invalid score limit accepted")
    all_bust = [event.call(1, "Alice", "roll", "6,6"), event.call(2, "Alice", "roll", "6,6"),
      event.call(3, "Bob", "roll", "6,6"), event.call(4, "Bob", "roll", "6,6")]
    replay = game.replay(session, all_bust, repo)
    check.call(replay.state[:round] == 2 && replay.state[:scores].values == [0, 0], "All-bust round awards points")
    tied_21 = [event.call(1, "Alice", "roll", "6,6"), event.call(2, "Alice", "roll", "4,5"),
      event.call(3, "Bob", "roll", "6,6"), event.call(4, "Bob", "roll", "4,5")]
    check.call(game.replay(session, tied_21, repo).state[:scores].values == [0, 0], "Tied 21s award points")
    fifteen = game.replay(session, [event.call(1, "Alice", "roll", "6,6"), event.call(2, "Alice", "roll", "1,2")], repo)
    check.call(game.dice_count(fifteen.state) == 2, "Changed to one die at 15 instead of 16")
    native = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::Source.new, server_random: true)
    status, plan = game.action_for({"action" => "roll"}, fifteen, "Alice", context: native)
    check.call(status == :ok && plan.events.first.random_request.values_at('count', 'sides') == [2, 6], "Wrong native random request")
    check.call(game.replay(session, [event.call(1, "Alice", "roll", "7,1")], repo).accepted_events.empty?, "Invalid die face accepted")
    check.call(game.game_shortcuts(fifteen, 'Alice').map(&:key).include?('s'), "Score shortcut missing")
    "Blackjack Dice: threshold, scoring, variants, replay, ties and turn validation passed"
  end
end

puts BlackjackDiceChecks.run! if $PROGRAM_NAME == __FILE__
