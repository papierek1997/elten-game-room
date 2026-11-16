require_relative "../../support/krowa"
require_relative "../../../lib/game_sounds"

run = KrowaTestGame.new
assert(run.automatic == :ok && run.replay.state[:phase] == :active, "prepare solo")
assert(run.guess("Carol", "kot") == :not_player, "observer submitted")
assert(run.guess("Alice", "koty") == :wrong_length, "length validation")
assert(run.guess("Alice", "las") == :ok && run.automatic == :ok, "wrong but legal attempt")
assert(run.guess("Alice", "las") == :duplicate, "duplicate attempt accepted")
assert(run.guess("Alice", "kot") == :ok && run.automatic == :ok, "winning guess")
assert(run.replay.state[:phase] == :revealing, "commit checked before reveal")
assert(run.automatic == :ok && run.replay.winner == "Alice", "solo reveal")
assert(run.replay.history.count { |entry| entry.kind == :solution } == 1, "repeated solution")

race = KrowaTestGame.new(variant: "race", players: %w[Alice Bob Carol])
race.automatic
race.context.now += 0.125
race.guess("Alice", "kot")
race.guess("Bob", "kot")
race.automatic; race.automatic
assert(race.replay.state[:results]["Alice"][:elapsed] == 125, "race loses millisecond clock")
assert(race.replay.state[:phase] == :active, "remaining contender denied first attempt")
race.guess("Carol", "las"); race.automatic
before = race.replay
race.automatic
assert(race.replay.state[:winners] == %w[Alice Bob], "co-winners lost")
%w[Alice Bob].each { |player| assert(GameRoomSounds.result_cue(race.game, before, race.replay, player) == "win_party", "#{player} hears loss") }
assert(GameRoomSounds.result_cue(race.game, before, race.replay, "Carol") == "lose_party", "loser hears win")

timed = KrowaTestGame.new(variant: "race", players: %w[Alice Bob Carol], scoring: "time")
timed.automatic
timed.context.now += 0.321
timed.guess("Alice", "kot"); timed.automatic
timed.context.now += 0.111
timed.guess("Bob", "kot"); timed.automatic; timed.automatic
assert(timed.replay.state[:winners] == ["Alice"], "time ranking changed")

tower = KrowaTestGame.new(variant: "tower", players: %w[Alice Bob])
tower.automatic
assert(tower.guess("Bob", "las") == :not_your_turn, "tower wrong turn")
tower.guess("Alice", "las"); tower.automatic
assert(tower.replay.current_player == "Bob", "tower turn did not advance")
tower.guess("Bob", "kot"); tower.automatic; tower.automatic
assert(tower.replay.state[:completed] == [{word: "kot", attempts: 2}], "tower completion")
first, last = tower.game.round_timing_event_ids(tower.replay, repository: tower.repository)
assert(first && last == tower.events.last['id'], 'word round duration does not stop at the accepted solution')
tower.automatic
assert(tower.replay.current_player == "Alice" && tower.replay.state[:round] == 2, "next word turn")
assert(tower.game.round_timing_event_ids(tower.replay, repository: tower.repository).last.nil?, 'new word keeps the previous round end time')
assert(tower.surrender("Bob") == :not_host, "non-host ended tower")
tower.surrender("Alice"); tower.automatic
assert(tower.replay.finished?, "tower surrender")

daily = KrowaTestGame.new(variant: "daily")
daily.context.now += 172_800 # Game epoch cannot choose the real calendar day.
assert(daily.automatic == :ok && daily.replay.state[:day] == "2026-09-18", "daily used game epoch")
assert(daily.game.save_game_error(daily.replay), "daily save offered")
assert(daily.game.table_join_error({"variant" => "daily"}, viewer: "Bob", owner: "Alice"), "daily observer allowed")
assert(daily.game.join_as_observer?({"variant" => "random"}, viewer: "Bob", owner: "Alice"), "random player not observer")
assert(!daily.game.role_selection_allowed?({"variant" => "random"}), "solo roles exposed")
assert(!daily.game.supports_bots?, "Krowa bots unexpectedly enabled")

failed = KrowaTestGame.new
failed.program.fail_write = true
assert(failed.automatic == :local_storage_unavailable, "storage exception escaped")
assert(failed.events.empty? && failed.replay.state[:phase] == :setup, "unwritten secret broadcast")
retrying = KrowaTestGame.new
selection = retrying.game.automatic_action(retrying.replay, "Alice", context: retrying.context)
first = retrying.game.action_for(selection, retrying.replay, "Alice", context: retrying.context)
again = retrying.game.action_for(selection, retrying.replay, "Alice", context: retrying.context)
assert(first.last.events.map(&:value) == again.last.events.map(&:value), "retry changed committed word")

expected = {"daily" => %w[variant], "random" => %w[variant length], "race" => %w[variant length race_scoring], "tower" => %w[variant]}
expected.each do |variant, keys|
  options = daily.game.normalize_options("variant" => variant)
  visible = daily.game.effective_option_definitions(options).select { |definition| daily.game.option_visible?(definition, options) }.map(&:key)
  assert(visible == keys, "irrelevant options for #{variant}: #{visible}")
end
puts "Krowa: four variants, milliseconds, co-winners/audio, membership, storage and options OK"
