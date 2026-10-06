require_relative "../../../lib/game_surfaces/specifications"
def _(text)
  text
end


require "json"
require_relative "../../../lib/game_random"
require_relative "../../../lib/game_bots"
require_relative "../../../lib/hidden_submissions"
require_relative "../../../lib/game_content"
require_relative "../../../content/languages"
require_relative "../../../content/quiz_pl_wikidata"
require_relative "../../../games/quiz_party"

class QuizRepository
  def initialize(players)
    @players = players
  end

  def players_for(_session)
    @players
  end

  def actor_of(event, _session = nil)
    event.fetch("actor")
  end

  def event_id(event)
    event.fetch("id")
  end
end

def assert(condition, message)
  raise message if !condition
end

def surface_action(kind, name, payload = {})
  GameSurfaces::Action.new(kind: kind, name: name, payload: payload)
end

def append_plan(events, plan, actor, now: 100)
  plan.events.each do |command|
    events << {
      "id" => events.length + 1,
      "actor" => actor,
      "action" => command.action,
      "value" => command.value,
      "created_at" => now
    }
  end
end

def draw_round(game, session, events, repository, context, owner, now:)
  draw_context = context.dup
  draw_context.now = now
  replay = game.replay(session, events, repository)
  action = game.automatic_action(replay, owner, context: draw_context)
  assert(action != nil, "the categories for the round were never drawn")
  status, plan = game.action_for(action, replay, owner, context: draw_context)
  assert(status == :ok, "the category draw was rejected")
  assert(plan.events.first.value.length <= 64, "the category draw exceeds the server value limit")
  append_plan(events, plan, owner, now: now)
  game.replay(session, events, repository)
end

game = GameRoomGames::QuizParty.new
fixture_registry = GameRoomContent::Registry.new
GameRoomContent.registry.languages.each { |language| fixture_registry.register_language(language) }
fixture_registry.register_pack(GameRoomContent.registry.pack('quiz.wikidata.pl'))
game.define_singleton_method(:content_registry) { fixture_registry }
players = ["Alice", "Bob"]
repository = QuizRepository.new(players)
vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
context = GameRoomGames::ActionContext.new(
  session_id: 7,
  table_id: 4,
  hidden_submissions: vault,
  random_source: GameRoomRandom::SeededSource.new(4242),
  now: 100
)

assert(game.id == "quiz", "the game exposes the wrong id")
assert(game.minimum_players == 2 && game.maximum_players == 8, "Quiz Party exposes the wrong player range")
assert(game.supports_bots?, "Quiz Party does not offer computer players")
assert(!game.perfect_information?, "hidden answers were exposed to tree search")
assert(game.rule_book.documents.map(&:id) == [:rules, :controls], "the rule book must expose rules and keyboard help")
assert(game.rule_book.sections.any? { |section| section.id == :bot_pacing }, "the shared bot timing rule is missing")

defaults = game.default_options
assert(defaults["answer_time"] == 20, "the default answer time is wrong")
assert(defaults["target_score"] == 15, "the default target score is wrong")
assert(defaults["content_language_id"] == "pl-PL", "the question language option was not offered")
assert(defaults["content_set_id"] == "quiz.wikidata", "the question set option was not offered")
language_definition = game.effective_option_definitions.find { |definition| definition.key == "content_language_id" }
assert(language_definition != nil && language_definition.kind == :choice, "the table cannot pick a question language")
assert(language_definition.choices.map(&:value) == ["pl-PL"], "the fixture's installed question languages are not offered as choices")
time_definition = game.effective_option_definitions.find { |definition| definition.key == "answer_time" }
assert(time_definition.kind == :choice, "the answer time is not a choice list")
assert(time_definition.choices.map(&:value) == [5, 6, 7, 8, 9, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60], "the answer time choices are wrong")
target_definition = game.effective_option_definitions.find { |definition| definition.key == "target_score" }
assert(target_definition.choices.map(&:value).min == 15, "the target score can be set below fifteen points")
assert(game.validation_error(defaults, player_count: 2) == nil, "a default table was rejected")
assert(game.validation_error(defaults.merge("target_score" => 10), player_count: 2) != nil, "a target score below fifteen was accepted")
assert(game.validation_error(defaults.merge("answer_time" => 3), player_count: 2) != nil, "an answer time below five seconds was accepted")
assert(game.normalize_options(JSON.parse(JSON.generate(defaults))) == defaults, "default options do not survive serialization")

options = game.normalize_options(defaults.merge("answer_time" => 5, "target_score" => 15))
session = { "options" => JSON.generate(options) }
events = []
replay = game.replay(session, events, repository)
assert(replay.state[:phase] == :drawing, "the match did not start by drawing categories")

replay = draw_round(game, session, events, repository, context, "Alice", now: 100)
assert(replay.state[:phase] == :choosing, "the match did not start with a category choice")
assert(replay.current_player == "Alice", "the first category chooser is wrong")
assert(replay.current_player == "Alice", "the chooser is not the active player")

choice_surface = game.surface_spec(replay, "Alice")
assert(choice_surface.mode == :single_choice, "the chooser did not receive a category list")
assert(choice_surface.submit_on_select == true, "choosing a category needs a second keystroke")
pack_categories = GameRoomContent.registry.pack("quiz.wikidata.pl")
  .data["questions"].map { |question| question["category"] }.uniq.sort
pack_category_counts = GameRoomContent.registry.pack("quiz.wikidata.pl")
  .data["questions"].group_by { |question| question["category"] }.transform_values(&:length)
offered_categories = choice_surface.options.map(&:id)
assert(offered_categories.length == replay.state[:choices].length, "the round offered a different number of categories than it drew")
assert((offered_categories - pack_categories).empty?, "the offered categories do not come from the pack")

assert(
  offered_categories.length == GameRoomGames::QuizParty::ROUND_CATEGORY_CHOICES,
  "the round offered #{offered_categories.length} categories instead of three"
)
assert(offered_categories.uniq.length == offered_categories.length, "the same category was drawn twice")
assert(
  offered_categories.length < pack_categories.length,
  "the draw offered every category in the pack, so nothing was actually drawn"
)

choice_surface.options.each do |option|
  expected = pack_category_counts.fetch(option.id)
  assert(
    option.label.include?(option.id) && option.label.include?(expected.to_s),
    "the category #{option.id} was offered without its question count: #{option.label}"
  )
  assert(option.label.include?("question"), "the category #{option.id} did not name what is being counted")
end
assert(
  replay.history.any? { |entry| entry.kind == :round_draw && entry.text.include?(offered_categories.first) },
  "the drawn categories were never announced in the history"
)

chosen_category = offered_categories.first
waiting_surface = game.surface_spec(replay, "Bob")
assert(waiting_surface.mode == :information, "a waiting player received an interactive surface")

undrawn_category = pack_categories.find { |category| !offered_categories.include?(category) }
assert(undrawn_category != nil, "the pack has no category outside the draw to test with")
assert(
  game.action_for(
    surface_action("question", "submit", "question_id" => choice_surface.id, "answer" => undrawn_category),
    replay,
    "Alice",
    context: context
  ).first == :invalid,
  "a category outside the draw was accepted"
)

status, plan = game.action_for(
  surface_action("question", "submit", "question_id" => choice_surface.id, "answer" => chosen_category),
  replay,
  "Alice",
  context: context
)
assert(status == :ok, "the category could not be chosen")
assert(plan.events.first.value.length <= 64, "the category event exceeds the server value limit")
append_plan(events, plan, "Alice")
replay = game.replay(session, events, repository)
assert(replay.state[:category] == chosen_category && replay.state[:phase] == :starting, "the chosen category was not stored")

status, plan = game.action_for(
  surface_action("question", "submit", "question_id" => choice_surface.id, "answer" => chosen_category),
  replay,
  "Bob",
  context: context
)
assert(status == :not_your_turn, "a player who was not choosing set the category")

start = game.automatic_action(replay, "Alice", context: context)
status, plan = game.action_for(start, replay, "Alice", context: context)
assert(status == :ok, "the first question could not start")
assert(plan.events.first.value.length <= 64, "the question event exceeds the server value limit")
forged_question_parts = plan.events.first.value.split(",")
forged_question_parts[3] = "999"
forged_question_event = {
  "id" => events.length + 1,
  "actor" => "Alice",
  "action" => "question",
  "value" => forged_question_parts.join(","),
  "created_at" => 100
}
forged_question_replay = game.replay(session, events + [forged_question_event], repository)
assert(
  forged_question_replay.state[:phase] == :answering && forged_question_replay.state[:deadline] == 105,
  "replay trusted a client-provided question deadline"
)
delayed_question_event = forged_question_event.merge(
  "value" => plan.events.first.value,
  "created_at" => 101
)
delayed_question_replay = game.replay(session, events + [delayed_question_event], repository)
assert(
  delayed_question_replay.state[:phase] == :answering && delayed_question_replay.state[:deadline] == 106,
  "replay rejected a valid question because the server timestamp differed from the client clock"
)
append_plan(events, plan, "Alice")
replay = game.replay(session, events, repository)
assert(replay.state[:phase] == :answering, "the question did not open for answers")
assert(replay.state[:deadline] == 105, "the answer deadline does not follow the table option")

question_surface = game.surface_spec(replay, "Bob")
assert(question_surface.mode == :single_choice, "an answering player did not receive four answers")
assert(question_surface.options.length == 4, "a question does not offer exactly four answers")
assert(question_surface.prompt_in_choices == true, "the answer list cannot be used to reread the question")
assert(question_surface.submit_on_select == true, "answering needs a second keystroke")
assert(question_surface.options.map(&:label).uniq.length == 4, "a question offered duplicate answers")
assert(game.surface_spec(replay, "Alice").options.map(&:label) == question_surface.options.map(&:label), "players saw the answers in a different order")

pack = GameRoomContent.registry.pack("quiz.wikidata.pl")
asked = pack.data["questions"].find { |question| question["id"] == replay.state[:question_id] }
question_entry = replay.history.reverse.find { |entry| entry.kind == :question }
assert(question_entry != nil && question_entry.text == asked["prompt"], "the spoken question has a numbering prefix")
assert(game.describe_event(events.last, repository, replay, "Bob") == [asked["prompt"]], "the live question announcement has a numbering prefix")
correct_label = asked["correct"]
correct_index = question_surface.options.index { |option| option.label == correct_label }
wrong_index = (0...4).find { |index| index != correct_index }
assert(correct_index != nil, "the correct answer is missing from the offered options")
assert(!game.automatic_action_due?(replay, "Alice", context: context), "the deadline fired before any answer")

early_close_event = {
  "id" => events.length + 1,
  "actor" => "Alice",
  "action" => "answers_closed",
  "value" => "round-1-question-1",
  "created_at" => 101
}
early_close_replay = game.replay(session, events + [early_close_event], repository)
assert(early_close_replay.state[:phase] == :answering, "replay closed answers before submissions or the deadline")

status, plan = game.action_for(
  surface_action("question", "submit", "question_id" => question_surface.id, "answer" => correct_index.to_s),
  replay,
  "Alice",
  context: context
)
assert(status == :ok, "Alice could not answer")
append_plan(events, plan, "Alice", now: 101)
replay = game.replay(session, events, repository)

status, plan = game.action_for(
  surface_action("question", "submit", "question_id" => question_surface.id, "answer" => wrong_index.to_s),
  replay,
  "Bob",
  context: context
)
assert(status == :ok, "Bob could not answer")
append_plan(events, plan, "Bob", now: 102)
replay = game.replay(session, events, repository)

assert(replay.state[:commitments].length == 2, "the answers were not committed")
assert(
  replay.accepted_events.none? { |event| event["value"].to_s == correct_index.to_s && event["action"] == "answer_commit" },
  "an answer was readable before the question closed"
)
assert(
  events.none? { |event| event["action"] == "answer_pick" },
  "an answer became public before the question closed"
)
assert(
  game.action_for(
    surface_action("question", "submit", "question_id" => question_surface.id, "answer" => correct_index.to_s),
    replay,
    "Bob",
    context: context
  ).first == :already_submitted,
  "a player answered the same question twice"
)

close = game.automatic_action(replay, "Alice", context: context)
status, plan = game.action_for(close, replay, "Alice", context: context)
assert(status == :ok, "the question did not close after everyone answered")
append_plan(events, plan, "Alice", now: 103)
replay = game.replay(session, events, repository)
assert(replay.state[:phase] == :revealing, "the question did not enter revealing")

early_finish_event = {
  "id" => events.length + 1,
  "actor" => "Alice",
  "action" => "question_finished",
  "value" => "1,1,0",
  "created_at" => 104
}
early_finish_replay = game.replay(session, events + [early_finish_event], repository)
assert(early_finish_replay.state[:phase] == :revealing, "replay scored the question before reveals or the timeout")

%w[Alice Bob].each do |player|
  reveal = game.automatic_action(replay, player, context: context)
  assert(reveal != nil, "#{player}'s answer was not revealed")
  status, plan = game.action_for(reveal, replay, player, context: context)
  assert(status == :ok && plan.events.length == 2, "#{player}'s reveal is incomplete")
  append_plan(events, plan, player, now: 104)
  replay = game.replay(session, events, repository)
end
assert(replay.state[:reveals].length == 2, "the revealed answers did not verify against their commitments")

finish = game.automatic_action(replay, "Alice", context: context)
status, plan = game.action_for(finish, replay, "Alice", context: context)
assert(status == :ok, "the question could not be scored")
append_plan(events, plan, "Alice", now: 105)
replay = game.replay(session, events, repository)
assert(replay.state[:scores]["Alice"] == 1, "a correct answer did not score one point")
assert(replay.state[:scores]["Bob"] == 0, "a wrong answer scored points")
assert(replay.state[:scores]["Bob"] >= 0, "a wrong answer produced a negative score")
assert(replay.state[:position] == 1 && replay.state[:phase] == :starting, "the round did not advance to the second question")
assert(replay.history.any? { |entry| entry.text.include?(correct_label) }, "the correct answer was never announced")

scored_at = events.last["created_at"].to_i
assert(
  replay.state[:resume_at].to_i == scored_at + GameRoomGames::QuizParty::NEXT_QUESTION_PAUSE,
  "the pause before the next question was not scheduled from the scoring event"
)
pause_context = context.dup
pause_context.now = scored_at + GameRoomGames::QuizParty::NEXT_QUESTION_PAUSE - 1
assert(
  game.automatic_action(replay, "Alice", context: pause_context) == nil,
  "the next question started before the pause had elapsed"
)
assert(
  !game.automatic_action_due?(replay, "Alice", context: pause_context),
  "the table was woken up before the pause had elapsed"
)
assert(
  game.send(:automatic_plan, "start_question", replay.state, "Alice", pause_context).first == :invalid,
  "a question could be started during the pause by planning it directly"
)
ready_context = context.dup
ready_context.now = scored_at + GameRoomGames::QuizParty::NEXT_QUESTION_PAUSE
ready_action = game.automatic_action(replay, "Alice", context: ready_context)
assert(
  ready_action != nil,
  "the next question never started after the pause"
)
assert(
  game.automatic_action_due?(replay, "Alice", context: ready_context),
  "the table was not woken up when the pause elapsed"
)
clockless_context = context.dup
clockless_context.now = nil
assert(
  game.automatic_action(replay, "Alice", context: clockless_context) != nil,
  "an unknown clock stalled the table instead of starting the next question"
)

status, ready_plan = game.action_for(ready_action, replay, "Alice", context: ready_context)
assert(status == :ok, "the next question was rejected after the owner's pause")
skewed_question = {
  "id" => 10_001,
  "actor" => "Alice",
  "action" => ready_plan.events.first.action,
  "value" => ready_plan.events.first.value,
  "created_at" => replay.state[:resume_at].to_i - 1
}
skewed_replay = game.replay(session, events + [skewed_question], repository)
assert(
  skewed_replay.state[:phase] == :answering && skewed_replay.state[:position] == 2,
  "a receiver rejected the next question when LiveSessions timestamps differed across clients"
)

assert(
  replay.history.none? { |entry| entry.kind == :submission },
  "the game announced who had answered before the question closed"
)
commit_event = events.find { |event| event["action"] == "answer_commit" }
assert(commit_event != nil, "the test never produced an answer_commit event")
assert(
  game.describe_event(commit_event, repository, replay, "Bob").empty?,
  "a submission was read out while the question was still open"
)

alice_view = game.history_entries_for_display(replay, "Alice").map(&:text)
bob_view = game.history_entries_for_display(replay, "Bob").map(&:text)
assert(
  alice_view.any? { |text| text == "You answered correctly." },
  "the correct player was not told they answered correctly"
)
assert(
  alice_view.any? { |text| text == "Bob answered incorrectly." },
  "a two player table did not name the other player's result"
)
assert(
  bob_view.any? { |text| text == "You answered incorrectly." },
  "the wrong player was not told they answered incorrectly"
)
assert(
  alice_view.none? { |text| text.include?("answered correctly.") && text.include?("1") },
  "a small table was given counts instead of names"
)

big_players = %w[Alice Bob Cecylia Dawid Ewa]
big_game = GameRoomGames::QuizParty.new
big_state = big_game.send(:initial_state, big_players, options)
big_state[:phase] = :revealing
big_state[:round] = 1
big_state[:position] = 1
big_state[:category] = pack.data["questions"].first["category"]
big_state[:question_id] = pack.data["questions"].first["id"]
big_correct = big_game.send(:correct_option_index, big_state)
big_state[:reveals] = {
  "Alice" => big_correct,
  "Bob" => (big_correct + 1) % 4,
  "Cecylia" => big_correct,
  "Dawid" => (big_correct + 2) % 4
}
big_replay = GameRoomGames::Replay.new(players: big_players, state: big_state)
big_entries = big_game.send(:question_result_history, big_state, 900, "Alice")
big_state[:history] = big_entries
big_replay.history = big_entries
alice_big = big_game.history_entries_for_display(big_replay, "Alice").map(&:text)
ewa_big = big_game.history_entries_for_display(big_replay, "Ewa").map(&:text)
assert(
  alice_big.any? { |text| text.start_with?("You answered correctly.") },
  "a large table did not tell the listener their own result first"
)
assert(
  alice_big.any? { |text| text.include?("2 answered correctly.") && text.include?("3 answered incorrectly.") },
  "a large table did not summarise the results as counts"
)
assert(
  ewa_big.any? { |text| text.start_with?("You answered incorrectly.") },
  "a player who never answered was not counted as incorrect"
)
assert(
  alice_big.none? { |text| text.include?("Bob") || text.include?("Cecylia") },
  "a large table read out individual names"
)
assert(
  big_game.history_entries_for_display(big_replay, "Alice").length ==
    big_game.history_entries_for_display(big_replay, "Ewa").length,
  "the personalised history has a different length for each viewer"
)

require_relative "../../../lib/game_sounds"

def quiz_cue(game, event, before, after, repository, viewer)
  GameRoomSounds.event_cue(
    game: game,
    event: event,
    before_replay: before,
    after_replay: after,
    repository: repository,
    viewer: viewer
  )
end

category_event = events.find { |event| event["action"] == "round_category" }
assert(category_event != nil, "the test never produced a round_category event")
assert(
  quiz_cue(game, category_event, replay, replay, repository, "Alice") == "draw",
  "choosing a new category did not play the category sound"
)
scored_event = events.find { |event| event["action"] == "question_finished" }
assert(scored_event != nil, "the test never produced a question_finished event")
assert(
  quiz_cue(game, scored_event, replay, replay, repository, "Alice") == "replay",
  "a correct answer did not confirm itself with a sound"
)
assert(
  quiz_cue(game, scored_event, replay, replay, repository, "Bob") == "quiz_wrong_answer",
  "a wrong answer did not play its own sound"
)
assert(quiz_cue(game, scored_event, replay, replay, repository, "Observer") == nil,
  "an observer heard another player's answer result sound")
commit_cue_event = events.find { |event| event["action"] == "answer_commit" }
assert(
  quiz_cue(game, commit_cue_event, replay, replay, repository, "Alice") == nil,
  "a sound revealed that somebody had answered while the question was open"
)

won_state = game.send(:initial_state, players, options)
won_state[:winner] = "Alice"
won_state[:winners] = ["Alice"]
won_replay = GameRoomGames::Replay.new(players: players, state: won_state, winner: "Alice", draw: false)
running_replay = GameRoomGames::Replay.new(players: players, state: game.send(:initial_state, players, options))
assert(
  quiz_cue(game, scored_event, running_replay, won_replay, repository, "Alice") == "win_party",
  "winning the match did not play the victory sound"
)
assert(
  quiz_cue(game, scored_event, running_replay, won_replay, repository, "Bob") == "lose_party",
  "losing the match did not play the defeat sound"
)
%w[replay draw win_party lose_party].each do |asset|
  assert(GameRoomSounds::ASSET_NAMES.include?(asset), "the quiz uses an unregistered sound #{asset}")
  assert(File.exist?(File.expand_path("../../../Audio/#{asset}.opus", __dir__)), "the sound file #{asset}.opus is missing")
end

2.times do |index|
  start_context = context.dup
  start_context.now = 110 + index * 10
  start = game.automatic_action(replay, "Alice", context: start_context)
  status, plan = game.action_for(start, replay, "Alice", context: start_context)
  assert(status == :ok, "question #{index + 2} could not start")
  append_plan(events, plan, "Alice", now: 110 + index * 10)
  replay = game.replay(session, events, repository)
  assert(replay.state[:category] == chosen_category, "the category changed inside a round")
  asked_question = pack.data["questions"].find { |question| question["id"] == replay.state[:question_id] }
  assert(asked_question["category"] == chosen_category, "a question came from another category")

  surface = game.surface_spec(replay, "Alice")
  index_of_correct = surface.options.index { |option| option.label == asked_question["correct"] }
  %w[Alice Bob].each do |player|
    answer = player == "Alice" ? index_of_correct : (index_of_correct + 1) % 4
    status, plan = game.action_for(
      surface_action("question", "submit", "question_id" => surface.id, "answer" => answer.to_s),
      replay,
      player,
      context: context
    )
    assert(status == :ok, "#{player} could not answer question #{index + 2}")
    append_plan(events, plan, player, now: 111 + index * 10)
    replay = game.replay(session, events, repository)
  end

  close = game.automatic_action(replay, "Alice", context: context)
  status, plan = game.action_for(close, replay, "Alice", context: context)
  append_plan(events, plan, "Alice", now: 112 + index * 10)
  replay = game.replay(session, events, repository)
  %w[Alice Bob].each do |player|
    reveal = game.automatic_action(replay, player, context: context)
    status, plan = game.action_for(reveal, replay, player, context: context)
    append_plan(events, plan, player, now: 113 + index * 10)
    replay = game.replay(session, events, repository)
  end
  finish = game.automatic_action(replay, "Alice", context: context)
  status, plan = game.action_for(finish, replay, "Alice", context: context)
  assert(status == :ok, "question #{index + 2} could not be scored")
  append_plan(events, plan, "Alice", now: 114 + index * 10)
  replay = game.replay(session, events, repository)
end

assert(replay.state[:completed_rounds] == 1, "a round did not end after three questions")
assert(replay.state[:scores]["Alice"] == 3, "three correct answers did not score three points")
assert(replay.state[:phase] == :drawing, "the second round did not draw new categories")
assert(replay.state[:choices].empty?, "the finished round kept its drawn categories")
assert(replay.state[:used_questions].uniq.length == 3, "a question repeated inside a round")

round_scored_at = events.last["created_at"].to_i
assert(
  replay.state[:resume_at].to_i == round_scored_at + GameRoomGames::QuizParty::NEXT_QUESTION_PAUSE,
  "the end of a round did not schedule the reading pause before the next draw"
)
round_pause_context = context.dup
round_pause_context.now = round_scored_at + GameRoomGames::QuizParty::NEXT_QUESTION_PAUSE - 1
assert(
  game.automatic_action(replay, "Alice", context: round_pause_context) == nil,
  "the next round was drawn before the pause had elapsed"
)

round_ready_context = context.dup
round_ready_context.now = round_scored_at + GameRoomGames::QuizParty::NEXT_QUESTION_PAUSE
round_ready_action = game.automatic_action(replay, "Alice", context: round_ready_context)
status, round_ready_plan = game.action_for(round_ready_action, replay, "Alice", context: round_ready_context)
assert(status == :ok, "the next round draw was rejected after the owner's pause")
skewed_round_draw = {
  "id" => 10_002,
  "actor" => "Alice",
  "action" => round_ready_plan.events.first.action,
  "value" => round_ready_plan.events.first.value,
  "created_at" => replay.state[:resume_at].to_i - 1
}
skewed_round_replay = game.replay(session, events + [skewed_round_draw], repository)
assert(
  skewed_round_replay.state[:phase] == :choosing,
  "a receiver rejected the next round when LiveSessions timestamps differed across clients"
)

replay = draw_round(
  game, session, events, repository, context, "Alice",
  now: round_scored_at + GameRoomGames::QuizParty::NEXT_QUESTION_PAUSE
)
assert(replay.state[:phase] == :choosing, "the second round did not open a category choice")
second_round_choices = replay.state[:choices]
assert(
  second_round_choices.length == GameRoomGames::QuizParty::ROUND_CATEGORY_CHOICES,
  "the second round did not draw three categories"
)
assert(replay.current_player == "Bob", "the category choice did not rotate to the other player")
second_surface = game.surface_spec(replay, "Bob")
assert(second_surface.options.map(&:id) == second_round_choices, "the second round offered categories it had not drawn")
assert(
  second_surface.options.all? { |option| option.label.include?("question") },
  "the second round dropped the question counts from the category list"
)

assert(
  game.turn_announcement(replay, "Bob") == "Choose a category.",
  "the chooser was not asked to choose a category"
)
assert(
  game.turn_announcement(replay, "Alice") == "Bob is choosing a category.",
  "the waiting player was not told who is choosing a category"
)
turn_entry = game.turn_transition_history_entry(nil, replay, event_id: 999)
assert(
  turn_entry != nil && turn_entry.text == "Bob is choosing a category.",
  "the history recorded a plain turn change for a category choice"
)

pending_state = game.send(:initial_state, players, options)
pending_state[:phase] = :answering
pending_state[:round] = 5
pending_state[:position] = 1
pending_state[:category] = pack.data["questions"].first["category"]
pending_state[:question_id] = pack.data["questions"].first["id"]
pending_state[:deadline] = 200
pending_replay = GameRoomGames::Replay.new(players: players, state: pending_state)
pending_submission = surface_action("question", "submit", "question_id" => "quiz-question-5-1", "answer" => "2")
pending_surface = Struct.new(:action) do
  def submission_action
    action
  end
end.new(pending_submission)
deadline_context = context.dup
deadline_context.now = 200
assert(
  game.automatic_surface_action(pending_replay, "Bob", surface: pending_surface, context: deadline_context) == nil,
  "an unconfirmed answer was submitted automatically when time expired"
)
assert(!game.automatic_action_due?(pending_replay, "Alice", context: deadline_context), "the host closed the question before answers could arrive")
grace_context = context.dup
grace_context.now = 200 + GameRoomGames::QuizParty::DEADLINE_SUBMISSION_GRACE
assert(game.automatic_action_due?(pending_replay, "Alice", context: grace_context), "the grace period never woke the game")
assert(
  game.timer_announcements(pending_replay, "Bob", now: 196).any? { |key, text, cue| key.include?("five") && text.include?("5") && cue == "buzzer2" },
  "the five-second warning is missing"
)
assert(
  game.timer_announcements(pending_replay, "Bob", now: 200).any? { |key, _| key.include?("expired") },
  "the time-up announcement is missing"
)

tie_state = game.send(:initial_state, players, options)
tie_state[:scores] = { "Alice" => 15, "Bob" => 15 }
tie_state[:completed_rounds] = 5
tie_history = []
winner, draw = game.send(:update_match_ending, tie_state, tie_history, 500)
assert(winner == nil && !draw, "a tied match ended without another round")
assert(tie_state[:final_round] == 6, "the tie-break round boundary is wrong")
tie_state[:scores]["Alice"] = 17
tie_state[:completed_rounds] = 6
winner, draw = game.send(:update_match_ending, tie_state, tie_history, 501)
assert(winner == "Alice", "a single leader above the target did not win")

below_state = game.send(:initial_state, players, options)
below_state[:scores] = { "Alice" => 14, "Bob" => 3 }
below_state[:completed_rounds] = 4
winner, draw = game.send(:update_match_ending, below_state, [], 502)
assert(winner == nil && !draw && below_state[:final_round] == nil, "the match ended below the target score")

bot = "bot:4:1"
bot_players = ["Alice", bot]
bot_game = GameRoomGames::QuizParty.new
bot_state = bot_game.send(:initial_state, bot_players, options)
bot_state[:phase] = :answering
bot_state[:round] = 1
bot_state[:position] = 1
bot_state[:category] = pack.data["questions"].first["category"]
bot_state[:question_id] = pack.data["questions"].first["id"]
bot_state[:deadline] = 0
bot_replay = GameRoomGames::Replay.new(players: bot_players, state: bot_state)
bot_actions = bot_game.legal_actions(bot_replay, bot, context: context)
assert(bot_actions.length == 4, "the computer was not offered every answer")
assert(bot_game.active_actors(bot_replay).include?(bot), "the computer was never asked to answer")
correct_for_bot = bot_game.send(:correct_option_index, bot_state)
assert(
  bot_actions.count { |action| bot_game.bot_action_score(bot_replay, bot, action) > 0.0 } == 1,
  "the computer scoring marks more than one answer as correct"
)

coordinator = GameRoomBots::Coordinator.new
hits = 0
trials = 400
trials.times do |index|
  trial_context = GameRoomGames::ActionContext.new(
    session_id: 7,
    table_id: 4,
    hidden_submissions: vault,
    random_source: GameRoomRandom::SeededSource.new(9_000 + index),
    now: 100
  )
  decision = coordinator.decide(game: bot_game, replay: bot_replay, actor: bot, context: trial_context)
  assert(decision != nil, "the computer refused to answer")
  hits += 1 if decision.action["answer"].to_i == correct_for_bot
end
accuracy = hits * 100.0 / trials
assert(accuracy >= 40.0, "the computer answered correctly only #{accuracy.round(1)}% of the time, below the required 40%")
assert(accuracy <= 85.0, "the computer is too strong at #{accuracy.round(1)}% and would never lose")

observation = bot_game.bot_observation(bot_replay, bot)
assert(!JSON.generate(observation).include?(pack.data["questions"].first["correct"]), "the computer observation leaks the correct answer")

stuck_state = game.send(:initial_state, players, options)
stuck_state[:phase] = :revealing
stuck_state[:round] = 3
stuck_state[:position] = 2
stuck_state[:category] = pack.data["questions"].first["category"]
stuck_state[:question_id] = pack.data["questions"].first["id"]
stuck_state[:deadline] = 300
stuck_state[:commitments] = { "Alice" => "a" * 64, "Bob" => "b" * 64 }
stuck_state[:reveals] = { "Alice" => 0 }
stuck_replay = GameRoomGames::Replay.new(players: players, state: stuck_state)
early_context = context.dup
early_context.now = 305
assert(
  game.automatic_action(stuck_replay, "Alice", context: early_context) == nil,
  "the question was scored while a reveal could still arrive"
)
assert(
  !game.automatic_action_due?(stuck_replay, "Alice", context: early_context),
  "the reveal window closed before it expired"
)
late_context = context.dup
late_context.now = 300 + GameRoomGames::QuizParty::REVEAL_TIMEOUT
assert(
  game.automatic_action_due?(stuck_replay, "Alice", context: late_context),
  "a missing reveal froze the table forever"
)
late_action = game.automatic_action(stuck_replay, "Alice", context: late_context)
assert(late_action != nil && late_action["action"] == "finish_question", "the stalled question was never scored")
status, plan = game.action_for(late_action, stuck_replay, "Alice", context: late_context)
assert(status == :ok, "a question with a missing reveal could not be scored")

small_game = GameRoomGames::QuizParty.new
smallest_category = pack.data["questions"].group_by { |question| question["category"] }
  .min_by { |_category, questions| questions.length }.first
science_ids = pack.data["questions"].select { |question| question["category"] == smallest_category }
  .map { |question| question["id"] }
exhausted_state = small_game.send(:initial_state, players, options)
exhausted_state[:phase] = :starting
exhausted_state[:round] = 9
exhausted_state[:position] = 0
exhausted_state[:category] = smallest_category
exhausted_state[:used_questions] = science_ids.dup
exhausted_replay = GameRoomGames::Replay.new(players: players, state: exhausted_state)
start = small_game.automatic_action(exhausted_replay, "Alice", context: context)
assert(start != nil, "an exhausted category never asked for a new question")
status, plan = small_game.action_for(start, exhausted_replay, "Alice", context: context)
assert(status == :ok, "an exhausted category could not start a question")
assert(science_ids.include?(plan.events.first.value.split(",")[2]), "the reopened pool asked a question from another category")

puts "Quiz Party tests passed: options, category rounds, hidden answers, scoring, deadlines and a #{accuracy.round(1)}% computer"
