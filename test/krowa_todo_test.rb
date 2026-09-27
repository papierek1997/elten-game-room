require_relative "support/ui"
require_relative "support/krowa_services"
require_relative "../games/krowa_support/leaderboards"
require_relative "../games/krowa_support/server_schema"
require_relative "../lib/game_surfaces"
require "date"

daily_schema = GameRoomGames::KrowaServerSchema::TABLES.fetch("krowa_daily_scores")
assert(daily_schema["visibility"] == "public" && daily_schema["columns"].keys.sort == %w[attempts day_key],
  "daily score schema must be public without a solution column")

bank = GameRoomGames::KrowaWordBank.default
%w[mural murale gej geje zapadnia zapadnie aronia aronie].each do |word|
  assert(bank.include?(word), "missing new noun: #{word}")
end
repository = GameRoomKrowa::WordRepository.default
%w[mural murale gej geje zapadnia zapadnie aronia aronie].each do |word|
  assert(repository.words_of_length(word.length).include?(word), "daily pool excludes new noun: #{word}")
end
assert(bank.daily(Time.utc(2026, 9, 25, 12)).last == "idy", "daily selection ignores the expanded pool")
assert(bank.daily(Time.utc(2026, 9, 26, 12)).last == "kuesty", "past daily word was not recalculated")
assert(bank.daily(Time.utc(2026, 9, 27, 12)).last == "listowia", "current daily word was not recalculated")

game = KrowaTestGame.new
{3 => 15, 4 => 24, 5 => 30, 6 => 42, 7 => 49, 8 => 64}.each do |length, count|
  assert(game.game.tower_attempt_limit(length) == count, "wrong tower limit for #{length} letters")
end

daily = KrowaTestGame.new(variant: "daily")
daily.automatic
local_noun = "z" * daily.replay.state[:length]
daily.context.local_data["dictionary"] = [local_noun]
assert(daily.guess("Alice", local_noun) == :unknown_noun, "daily accepted a local noun")
assert(daily.guess("Alice", local_noun, adding: true) == :add_word_unavailable, "daily allowed adding a noun")
daily_answer = daily.game.surface_spec(daily.replay, "Alice").parts.find { |part| part.id == "answer" }
assert(daily_answer && daily_answer.surface.extra_commands.empty?, "daily shows the add-noun button")
random = KrowaTestGame.new
random.automatic
random.context.local_data["dictionary"] = ["fuf"]
assert(random.guess("Alice", "fuf") == :ok, "random word lost the local dictionary")

tables = KrowaTestTables.new
store = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: bank, user: "Alice")
assert(store.publish_daily("2026-09-26", 7) == :unavailable, "unclaimed daily result published")
assert(store.record_daily_open("2026-09-26") == :opened, "past daily claim failed")
assert(store.publish_daily("2026-09-26", 7) == :published, "daily result not published")
assert(store.publish_daily("2026-09-26", 8) == :unchanged, "worse daily result published")
assert(store.publish_daily("2026-09-26", 6) == :published, "better daily result rejected")
assert(store.record_daily_open("2026-09-27") == :opened, "current daily claim failed")
assert(store.publish_daily("2026-09-27", 9) == :published, "current daily result not published")
scores = tables.fetch("krowa_daily_scores")
scores.user = "Bob"
scores.insert("day_key" => 20260926, "attempts" => 5)
scores.insert("day_key" => 20260926, "attempts" => 4)
assert(scores.rows.none? { |row| row.key?("word") }, "daily score records expose the answer")
assert(store.daily_days == %w[2026-09-27 2026-09-26], "historical dates missing or duplicated")
rank = store.daily_ranking("2026-09-26")
assert(rank.map { |row| [row["__insertion_user"], row["attempts"]] } == [["Bob", 4], ["Alice", 6]],
  "daily ranking did not retain each person's best score")

leaderboards = GameRoomGames::KrowaLeaderboardClient.new(game.program, game.game, store: store)
rows = leaderboards.send(:daily_date_rows, %w[2026-09-27 2026-09-26], "2026-09-27")
assert(rows == [["2026-09-27", ""], ["2026-09-26", "kuesty"]], "daily date list reveals today's answer")
today = leaderboards.send(:daily_ranking_header, "2026-09-27", "2026-09-27")
old = leaderboards.send(:daily_ranking_header, "2026-09-26", "2026-09-27")
assert(!today.include?("listowia") && old.include?("kuesty"), "daily ranking headers reveal or hide the wrong word")

501.times do |index|
  scores.user = "Player#{index}"
  scores.insert("day_key" => 20260925, "attempts" => index + 1)
end
assert(store.daily_ranking("2026-09-25").length == 501, "daily player rankings stop at the first page")
501.times do |index|
  day = Date.new(2024, 1, 1) + index
  scores.insert("day_key" => day.strftime("%Y%m%d").to_i, "attempts" => 1)
end
assert(store.daily_days.length == 504, "historical daily rankings stop at the first page")
assert(scores.queries.any? { |query| query[:offset] == 500 }, "daily leaderboard did not paginate")

puts "Krowa: new nouns in daily pool, local dictionary restriction, tower limits and daily rankings OK"
