require_relative "../../support/sequence_random"

require_relative "../../support/categories"

game = GameRoomGames::Categories.new
players = ["Alice", "Bob", "Carol"]
repository = CategoriesRepository.new(players)
storage = HiddenSubmissions::MemoryStorage.new
vault = HiddenSubmissions::Vault.new(storage)
random = GameRoomRandom::SequenceSource.new([1, 1])
context = GameRoomGames::ActionContext.new(
  session_id: 7,
  table_id: 4,
  hidden_submissions: vault,
  random_source: random,
  now: 100
)
events = []

assert(game.minimum_players == 2 && game.maximum_players == 8, "Categories exposes the wrong player range")
assert(!game.supports_bots?, "Categories unexpectedly supports bots")
assert(game.rule_book.sections.map(&:id).include?(:pools), "Categories rules do not describe category pools")
assert(game.rule_book.sections.map(&:id).include?(:finish), "Categories rules do not describe tie variants")
assert(game.default_options["judge_mode"] == "rotating", "Categories has the wrong default judge mode")
assert(game.default_options["answer_language"] == "pl", "Categories has the wrong default answer language")
assert(game.default_options["category_set"] == "easy", "Categories has the wrong default category pool")
assert(game.default_options["round_category_count"] == 6, "Categories has the wrong default round size")
assert(game.validation_error(game.default_options, player_count: 2) == nil, "a two-person match was rejected")

custom_options = game.normalize_options(
  game.default_options.merge(
    "category_set" => "custom",
    "custom_categories" => ["country", "city"],
    "round_category_count" => 2
  )
)
assert(custom_options["custom_categories"] == "5", "custom categories were not stored as a compact decimal mask")
assert(game.validation_error(custom_options, player_count: 2) == nil, "a valid custom category pool was rejected")
assert(game.options_from_json(JSON.generate(custom_options)) == custom_options, "custom categories did not survive an options round trip")
invalid_custom_options = custom_options.merge("round_category_count" => 3)
assert(game.validation_error(invalid_custom_options, player_count: 2) != nil, "a round larger than its custom pool was accepted")
assert(JSON.generate(game.default_options).length <= 256, "default Categories options exceed the server field limit")
assert(JSON.generate(custom_options).length <= 256, "custom Categories options exceed the server field limit")
large_round_categories = GameRoomGames::Categories::CATEGORY_IDS.last(9)
encoded_categories = game.send(:encode_round_categories, large_round_categories)
round_value = [1, 1, 0, "A", 2_000_000_000, encoded_categories].join(",")
assert(round_value.length <= 64, "a nine-category round still exceeds the server event limit")
assert(
  game.send(:decode_round_categories, encoded_categories) == large_round_categories,
  "compact round categories did not decode to their original values"
)
assert(
  game.send(:decode_round_categories, "country.city") == %w[country city],
  "the compact format broke an existing dotted category round"
)

options = custom_options.merge("round_time" => 90, "target_score" => 100)
session = { "options" => JSON.generate(options) }
replay = game.replay(session, events, repository)
start = game.automatic_action(replay, "Alice", context: context)
status, plan = game.action_for(start, replay, "Alice", context: context)
assert(status == :ok, "the first round could not start")
append_plan(events, plan, "Alice", now: 100)
replay = game.replay(session, events, repository)
assert(replay.state[:phase] == :answering, "the first round did not enter answering")
assert(replay.state[:judge] == "Alice", "the rotating judge started in the wrong seat")
assert(replay.state[:letter] == "A" && replay.state[:deadline] == 190, "the round letter or deadline is wrong")
assert(replay.state[:round_categories] == %w[country city], "the configured categories were not selected for the round")
assert(game.automatic_action_due?(replay, "Alice", context: context) == false, "the answer deadline fired too early")
answer_surface = game.surface_spec(replay, "Bob")
assert(answer_surface.is_a?(GameSurfaces::AnswerSheetSpec), "an answering player did not receive the answer sheet")
assert(
  answer_surface.fields.map(&:label) == [
    "Country for letter A",
    "City for letter A"
  ],
  "answer field labels do not include the drawn letter"
)
judge_surface = game.surface_spec(replay, "Alice")
assert(!judge_surface.is_a?(GameSurfaces::CompositeSpec), "the judge still received a manual close-answering button")

answers = {
  "Bob" => { "country" => "Austria", "city" => "Athens", "name" => "", "animal" => "", "plant" => "", "thing" => "" },
  "Carol" => { "country" => "Argentina", "city" => "Athens", "name" => "", "animal" => "", "plant" => "", "thing" => "" }
}
answers.each do |player, payload|
  action = surface_action("answer_sheet", "submit", "answers" => payload)
  status, plan = game.action_for(action, replay, player, context: context)
  assert(status == :ok, "#{player} could not submit answers")
  append_plan(events, plan, player, now: 110)
  replay = game.replay(session, events, repository)
end
assert(replay.state[:commitments].length == 2, "answer commitments were not recorded")
assert(replay.accepted_events.none? { |event| event["value"] == "Athens" }, "an answer was public before writing closed")

close = game.automatic_action(replay, "Alice", context: context)
status, plan = game.action_for(close, replay, "Alice", context: context)
assert(status == :ok, "answering did not close after every submission")
append_plan(events, plan, "Alice", now: 111)
replay = game.replay(session, events, repository)
assert(replay.state[:phase] == :revealing, "the round did not enter revealing")

%w[Bob Carol].each do |player|
  reveal = game.automatic_action(replay, player, context: context)
  assert(reveal != nil, "#{player}'s reveal was not prepared")
  status, plan = game.action_for(reveal, replay, player, context: context)
  assert(status == :ok && plan.events.length == 3, "#{player}'s reveal is incomplete")
  append_plan(events, plan, player, now: 112)
  replay = game.replay(session, events, repository)
  assert(
    game.participant_status(replay, player) == nil,
    "a revealed answer still appeared as a spoken participant status"
  )
end
assert(replay.state[:reveals].length == 2, "revealed answers did not verify")
assert(
  replay.history.none? { |entry| entry.kind == :reveal },
  "revealing answers still produced a redundant public announcement"
)

begin_review = game.automatic_action(replay, "Alice", context: context)
status, plan = game.action_for(begin_review, replay, "Alice", context: context)
assert(status == :ok, "review did not start after every reveal")
append_plan(events, plan, "Alice", now: 113)
replay = game.replay(session, events, repository)
assert(replay.state[:phase] == :review, "the round did not enter review")
assert(
  replay.history.none? { |entry| entry.kind == :review_start },
  "review start still produced a second announcement beside the named turn transition"
)
surface = game.surface_spec(replay, "Alice")
review_surface = if surface.is_a?(GameSurfaces::CompositeSpec)
  surface.parts.map(&:surface).find { |candidate| candidate.is_a?(GameSurfaces::ReviewSpec) }
else
  surface
end
assert(review_surface.is_a?(GameSurfaces::ReviewSpec), "the judge did not receive the review interface")
assert(review_surface.items.length == 3, "identical answers were not grouped")
duplicate_group = review_surface.items.find { |item| item.answer == "Athens" }
assert(duplicate_group.author.empty?, "the judge can see the authors of a grouped answer")
assert(duplicate_group.status == "identical answer from 2 players", "a grouped answer has no group description")
assert(review_surface.decisions.map(&:id) == %w[unique partial duplicate incorrect], "the judge lost manual 2/1/0 decisions")
assert(duplicate_group.decision_ids == %w[duplicate incorrect], "an identical group exposes an invalid assessment")
single_group = review_surface.items.find { |item| item.answer == "Austria" }
assert(single_group.decision_ids == %w[unique partial incorrect], "a single answer exposes an invalid assessment")
assert(review_surface.submit_label == "Finish review" && review_surface.read_only == false, "the review is not a finishable form")

viewer_surface = game.surface_spec(replay, "Bob")
assert(viewer_surface.is_a?(GameSurfaces::QuestionSpec), "a non-judge still received the answer review interface")
assert(viewer_surface.mode == :information, "waiting players did not receive a quiet review status")
assert(replay.history.none? { |entry| entry.kind == :revealed_answer }, "answers were revealed before the judge assessed them")

final_decisions = {}
review_surface.items.each do |item|
  initial_decision = item.answer == "Athens" ? "incorrect" : "unique"
  final_decisions[item.id] = initial_decision
  action = surface_action("review", "change", "item_id" => item.id, "decision" => initial_decision)
  status, plan = game.action_for(action, replay, "Alice", context: context)
  assert(status == :ok, "the judge could not assess a grouped answer")
  append_plan(events, plan, "Alice", now: 114)
  replay = game.replay(session, events, repository)
  assert(game.describe_event(events.last, repository, replay, "Alice") == ["Assessed."], "the judge did not receive the concise local confirmation")
  assert(game.describe_event(events.last, repository, replay, "Bob").length == 1, "another player did not hear a confirmed assessment")
  review_text = replay.history.reverse.find { |entry| entry.kind == :review }.text
  expected_players = item.answer == "Athens" ? %w[Bob Carol] : [item.answer == "Austria" ? "Bob" : "Carol"]
  assert(expected_players.all? { |player| review_text.include?(player) }, "a confirmed assessment did not name its answer authors")
end

action = surface_action("review", "change", "item_id" => duplicate_group.id, "decision" => "duplicate")
status, plan = game.action_for(action, replay, "Alice", context: context)
assert(status == :ok, "the judge could not change an assessment")
append_plan(events, plan, "Alice", now: 114)
replay = game.replay(session, events, repository)
final_decisions[duplicate_group.id] = "duplicate"
assert(replay.history.any? { |entry| entry.text.include?("changed the decision") }, "an assessment change was not announced")
assert(game.automatic_action(replay, "Alice", context: context) == nil, "the round was scored before Finish review")

status, plan = game.action_for(
  surface_action("review", "finish", "decisions" => final_decisions),
  replay,
  "Alice",
  context: context
)
assert(status == :ok, "the judge could not finish the review")
assert(plan.events.length == 1 && plan.events.first.action == "review_commit", "the final review was not committed atomically")
append_plan(events, plan, "Alice", now: 114)
replay = game.replay(session, events, repository)
assert(
  replay.history.none? { |entry| entry.kind == :revealed_answer },
  "finishing the review repeated every assessed answer"
)

score = game.automatic_action(replay, "Alice", context: context)
status, plan = game.action_for(score, replay, "Alice", context: context)
assert(status == :ok && plan.events.length == 3, "round scoring did not create one score per player and an ending")
append_plan(events, plan, "Alice", now: 115)
replay = game.replay(session, events, repository)
assert(replay.state[:scores]["Bob"] == 3 && replay.state[:scores]["Carol"] == 3, "the 2/1/0 scoring is wrong")
assert(replay.state[:completed_rounds] == 1 && replay.state[:phase] == :round_complete, "the completed round did not advance")
assert(replay.history.count { |entry| entry.kind == :score } == 2, "concise round score summaries were removed")

context.now = replay.state[:resume_at]
next_round = game.automatic_action(replay, "Alice", context: context)
status, plan = game.action_for(next_round, replay, "Alice", context: context)
assert(status == :ok, "the second round could not start")
append_plan(events, plan, "Alice", now: 120)
replay = game.replay(session, events, repository)
assert(replay.state[:round] == 2 && replay.state[:judge] == "Bob", "the rotating judge did not advance")
assert(replay.state[:letter] != "A", "a letter repeated before the language pool was exhausted")

timeout_context = context.dup
timeout_context.now = replay.state[:deadline]
assert(!game.automatic_action_due?(replay, "Alice", context: timeout_context), "the host closed answers before clients could submit their fields")
timeout_context.now = replay.state[:deadline] + GameRoomGames::Categories::DEADLINE_SUBMISSION_GRACE
assert(game.automatic_action_due?(replay, "Alice", context: timeout_context), "the answer deadline grace period did not wake the game")

pending_state = game.send(:initial_state, players, options)
pending_state[:phase] = :answering
pending_state[:round] = 3
pending_state[:attempt] = 3
pending_state[:deadline] = 200
pending_state[:letter] = "B"
pending_state[:round_categories] = %w[country city]
pending_state[:active_players] = ["Bob", "Carol"]
pending_replay = GameRoomGames::Replay.new(players: players, state: pending_state)
submission = surface_action("answer_sheet", "submit", "answers" => { "country" => "Belgium", "city" => "Brussels" })
surface = Struct.new(:action) do
  def submission_action
    action
  end
end.new(submission)
deadline_context = context.dup
deadline_context.now = 200
assert(
  game.automatic_surface_action(pending_replay, "Bob", surface: surface, context: deadline_context).equal?(submission),
  "the current answer fields were not submitted when time expired"
)
announcements = game.timer_announcements(pending_replay, "Bob", now: 180)
assert(announcements.any? { |key, text| key.include?("twenty") && text.include?("20") }, "the 20-second warning is missing")
assert(game.timer_announcements(pending_replay, "Bob", now: 200).any? { |key, _| key.include?("expired") }, "the time-up announcement is missing")

tie_state = game.send(:initial_state, %w[Alice Bob Carol Dave], game.default_options.merge("tie_mode" => "extra_cycle"))
tie_state[:scores] = { "Alice" => 12, "Bob" => 12, "Carol" => 4, "Dave" => 3 }
tie_state[:completed_rounds] = 4
tie_state[:final_end_round] = 4
tie_history = []
winner, draw = game.send(:update_match_ending, tie_state, tie_history, 500)
assert(winner == nil && !draw, "a tied lead ended without a tie-break")
assert(tie_state[:tie_break_players] == %w[Alice Bob], "lower-scoring players remained in the tie-break")
judge = %w[Alice Bob Carol Dave][game.send(:judge_index, tie_state[:options], %w[Alice Bob Carol Dave], 5, tie_state)]
assert(%w[Carol Dave].include?(judge), "the tie-break judge was not selected from eliminated players")
assert(game.send(:contestants_for_round, %w[Alice Bob Carol Dave], judge, tie_state) == %w[Alice Bob], "the tie-break includes players below the tied lead")


cycle_game = GameRoomGames::Categories.new
cycle_players = ["Alice", "Bob"]
cycle_repository = CategoriesRepository.new(cycle_players)
cycle_options = cycle_game.table_creation_options("category_set" => "custom", "custom_categories" => ["country"],
  "round_category_count" => 1, "target_score" => 2, "tie_mode" => "shared")
cycle_session = { "options" => JSON.generate(cycle_options) }
cycle_context = GameRoomGames::ActionContext.new(
  session_id: 8,
  table_id: 5,
  hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
  random_source: GameRoomRandom::SequenceSource.new([1, 1]),
  now: 100
)
cycle_events = []
cycle_replay = play_unique_round(
  cycle_game,
  cycle_session,
  cycle_repository,
  cycle_events,
  cycle_context,
  owner: "Alice",
  judge: "Alice",
  answerer: "Bob"
)
assert(!cycle_replay.finished?, "the rotating match ended before every player had judged")
assert(cycle_replay.state[:final_end_round] == 2, "the final judge cycle has the wrong boundary")
cycle_replay = play_unique_round(
  cycle_game,
  cycle_session,
  cycle_repository,
  cycle_events,
  cycle_context,
  owner: "Alice",
  judge: "Bob",
  answerer: "Alice"
)
assert(cycle_replay.draw && cycle_replay.state[:winners].length == 2, "a configured shared victory was not preserved")

# The last unused letter is a deterministic choice, not a one-sided die.
GameRoomGames::Categories::LANGUAGE_LETTERS.each do |language, letters|
  last_session = { "options" => JSON.generate(options.merge("answer_language" => language)) }
  last_replay = game.replay(last_session, [], repository)
  last_replay.state[:used_letters] = letters[0...-1]
  last_context = context.dup
  last_context.random_source = GameRoomRandom::SequenceSource.new([])
  action = game.automatic_action(last_replay, "Alice", context: last_context)
  status, plan = game.action_for(action, last_replay, "Alice", context: last_context)
  assert(status == :ok && plan.events.first.value.split(",")[3] == letters.last,
    "the last unused #{language} letter could not start a round")
  last_replay.state[:used_letters] = letters.dup
  last_context.random_source = GameRoomRandom::SequenceSource.new([1])
  status, plan = game.action_for(action, last_replay, "Alice", context: last_context)
  assert(status == :ok && plan.events.first.value.split(",")[3] == letters.first,
    "the exhausted #{language} alphabet did not reset")
end

puts "Categories tests passed"

# Visibility of custom categories for built-in and user-defined pools.
categories_game = GameRoomGames::Categories.new
custom_categories = categories_game.option_definitions.find { |definition| definition.key == "custom_categories" }
assert(!categories_game.option_visible?(custom_categories, categories_game.default_options),
  "custom Categories options are visible for a built-in pool")
assert(categories_game.option_visible?(custom_categories, categories_game.default_options.merge("category_set" => "custom")),
  "custom Categories options stay hidden for the custom pool")
puts 'PASS Categories option visibility'
