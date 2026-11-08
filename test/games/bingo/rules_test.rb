require_relative "../../support/bingo"
include BingoChecksSupport

game = GameRoomGames::Bingo.new
repo = BingoChecksSupport::Repository.new(%w[Alice Bob])
session = bingo_session(game, variant: "75", marking: "manual", pattern: "line")
start = bingo_event(1, "Alice", "start", 'a' * 32)
events = [start]
initial = game.replay(session, events, repo)
check(initial.state[:phase] == :drawing && initial.state[:tickets].size == 2, "Missing tickets")
check(game.required_decision_key(nil, "Alice").nil?, "Nil replay decision")
check(game.action_for({"action" => "draw"}, initial, "Bob").first == :not_your_turn, "Wrong caller")
events << bingo_event(2, "Alice", "draw", "1")
called = game.replay(session, events, repo)
check(called.state[:called] == [1] && !called.state[:remaining].include?(1), "Ball not removed from drum")
check(game.active_actors(called) == repo.players, "Manual input is not simultaneous")
check(game.required_decision_key(called, "Alice"), "Manual marking decision missing")
check(game.turn_transition_history_entry(initial, called, event_id: 2).nil?, "Simultaneous marking announced an individual turn")
check(game.action_for({"action" => "claim", "call" => 1, "stage" => 0}, called, "Alice").first == :invalid_claim, "False bingo accepted")
number = called.state[:tickets]["Alice"].find { |n| n && n > 1 }
check(game.action_for({"action" => "mark", "number" => number, "call" => 1, "stage" => 0}, called, "Alice").first == :invalid_mark, "Uncalled number marked")
check(game.replay(session, events + [events.last], repo).state == called.state, "Duplicate draw changed game")
events << bingo_event(3, "Bob", "ready", "1|0")
after_bob = game.replay(session, events, repo)
check(game.concurrent_session_input?(called, after_bob, {"action" => "ready"}), "Concurrent same-call readiness rejected")
check(game.current_turn_shortcut_text(after_bob, "Bob") == "Waiting for players to finish marking.", "Ready player still told to mark numbers")
check(!game.concurrent_session_input?(called, after_bob, {"action" => "draw"}), "Caller wrongly concurrent")
events << bingo_event(4, "Alice", "ready", "1|0")
next_call = game.replay(session, events, repo)
check(next_call.state[:phase] == :drawing, "Ready barrier did not release next draw")
check(game.action_for({"action" => "ready", "call" => 1, "stage" => 0}, next_call, "Bob").first != :ok, "Old ready accepted")
check(game.replay(session, events + [bingo_event(5, "Alice", "draw", "75")], repo).state == next_call.state, "Out-of-range index accepted after removal")

auto_session = bingo_session(game, variant: "30", marking: "automatic", ball_interval: 5)
auto_initial = game.replay(auto_session, [start], repo)
early = GameRoomGames::ActionContext.new(now: 104, random_source: GameRoomRandom::SeededSource.new(4), server_random: true)
due = early.dup
due.now = 105
check(game.automatic_action(auto_initial, "Alice", context: early).nil?, "Draw not paced")
status, plan = game.action_for({"action" => "draw"}, auto_initial, "Alice", context: due)
check(status == :ok && plan.events.first.random_request['sides'] == 30, "Missing native server draw")
check(GameRoomServerRandom.required?("bingo", plan.events), "Caller bypasses native randomness")
bad = bingo_event(2, "Alice", "draw", "1", time: 105).merge('__server_random' => plan.events.first.random_request.merge('sides' => 29))
check(game.replay(auto_session, [start, bad], repo).accepted_events.size == 1, "Wrong pool-size metadata accepted")
no_clock = auto_initial.dup
no_clock.state = auto_initial.state.merge(next_at: nil)
check(game.automatic_action(no_clock, "Alice", context: due).nil?, "Missing native clock made the draw due")

# Keep both full tickets unclaimed until the final call to exercise tied claims.
manual30 = bingo_session(game, variant: "30", marking: "manual")
last_events = [start]
append = ->(actor, action, value) { last_events << bingo_event(last_events.size + 1, actor, action, value) }
29.times do |index|
  append.call("Alice", "draw", "1")
  repo.players.each { |player| append.call(player, "ready", "#{index + 1}|0") }
end
last = game.replay(manual30, last_events, repo)
status, last_plan = game.action_for({"action" => "draw"}, last, "Alice", context: due)
check(status == :ok && last_plan.events.first.random_request['sides'] == 2, "Final ball bypasses native two-sided dice")
last_events << bingo_event(last_events.size + 1, "Alice", "draw", "2").merge('__server_random' => last_plan.events.first.random_request)
last = game.replay(manual30, last_events, repo)
check(last.state[:called] == (1..30).to_a && last.state[:remaining].empty?, "Final equivalent index did not draw the last ball")
repo.players.each do |player|
  last.state[:tickets][player].each { |number| append.call(player, "mark", "30|0|#{number}") }
  append.call(player, "claim", "30|0")
end
tie = game.replay(manual30, last_events, repo)
check(tie.finished? && tie.draw && tie.state[:awards].last[:players] == repo.players, "Same-call bingo claims did not share the result")
check(tie.accepted_events.size == last_events.size, "Final-call claim events were rejected")
check(game.validation_error({"ball_interval" => 0}) != nil, "Zero draw interval accepted")
check(game.validation_error({"variant" => "90", "marking" => "manual"}).nil?, "Valid variant rejected")
puts "Bingo rules: authenticated calls, no replacement, actor validation, pacing, manual barrier and stale inputs passed"
