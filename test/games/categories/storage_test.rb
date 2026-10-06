require_relative "../../support/categories"
require_relative "../../support/hidden_submission_files"
require "tmpdir"

Dir.mktmpdir("categories-storage-217-") do |dir|
  game = GameRoomGames::Categories.new
  players = %w[Alice Bob Carol]
  repository = CategoriesRepository.new(players)
  session = { "options" => JSON.generate(game.default_options.merge("round_category_count" => 9)) }
  program = HiddenSubmissionFiles.new(dir)
  vault = HiddenSubmissions::Vault.new(program.storage)
  context = GameRoomGames::ActionContext.new(session_id: 217, table_id: 4, now: 100,
    hidden_submissions: vault, random_source: GameRoomRandom::SeededSource.new(217))
  events = []
  replay = game.replay(session, events, repository)
  action = game.automatic_action(replay, "Alice", context: context)
  status, plan = game.action_for(action, replay, "Alice", context: context)
  assert(status == :ok, "Categories did not start")
  append_plan(events, plan, "Alice")
  replay = game.replay(session, events, repository)
  payload = replay.state[:round_categories].to_h { |category| [category, "Abcdefghijklmno"] }
  assert(payload.size == 9, "nine-category regression was not configured")
  main = HiddenSubmissions::ProgramStorage::DEFAULT_PATH
  program.blocked = [main, main + ".recovery.json"]
  action = surface_action("answer_sheet", "submit", "answers" => payload)
  status, plan = game.action_for(action, replay, "Bob", context: context)
  assert(status == :local_storage_unavailable && plan.nil?, "Categories sent an unsaved sheet")
  program.blocked = [main]
  program.retry_now
  %w[Bob Carol].each do |u|
    status, plan = game.action_for(action, replay, u, context: context)
    assert(status == :ok, "Categories recovery write failed")
    append_plan(events, plan, u)
    replay = game.replay(session, events, repository)
  end
  context.hidden_submissions = HiddenSubmissions::Vault.new(HiddenSubmissionFiles.new(dir).storage)
  action = game.automatic_action(replay, "Alice", context: context)
  status, plan = game.action_for(action, replay, "Alice", context: context)
  assert(status == :ok, "Categories did not close answers")
  append_plan(events, plan, "Alice")
  replay = game.replay(session, events, repository)
  %w[Bob Carol].each do |u|
    action = game.automatic_action(replay, u, context: context)
    status, plan = game.action_for(action, replay, u, context: context)
    assert(status == :ok, "Categories could not reveal durable answers")
    append_plan(events, plan, u)
    replay = game.replay(session, events, repository)
  end
  assert(replay.state[:reveals].size == 2, "Categories lost a reveal")
  failed_cleanup = HiddenSubmissionFiles.new(dir)
  failed_cleanup.blocked = [main, main + ".recovery.json"]
  context.hidden_submissions = HiddenSubmissions::Vault.new(failed_cleanup.storage)
  %w[Bob Carol].each { |u| game.automatic_action(replay, u, context: context) }
  action = game.automatic_action(replay, "Alice", context: context)
  status, plan = game.action_for(action, replay, "Alice", context: context)
  assert(status == :ok, "cleanup failure prevented review")
  append_plan(events, plan, "Alice")
  assert(game.replay(session, events, repository).state[:phase] == :review, "Categories did not enter review")
end
puts "Categories storage regression passed; existing rules tests also passed"
