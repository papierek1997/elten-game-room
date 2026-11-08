require_relative "../../lib/game_surfaces/specifications"
def _(text)
  text
end


require "json"
require_relative "../../lib/game_random"
require_relative "../../lib/hidden_submissions"
require_relative "../../games/categories"

class CategoriesRepository
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

def play_unique_round(game, session, repository, events, context, owner:, judge:, answerer:)
  replay = game.replay(session, events, repository)
  context.now = [context.now.to_i, replay.state[:resume_at].to_i].max
  action = game.automatic_action(replay, owner, context: context)
  status, plan = game.action_for(action, replay, owner, context: context)
  raise "round start failed" if status != :ok
  append_plan(events, plan, owner, now: context.now)
  replay = game.replay(session, events, repository)

  assert(replay.state[:round_categories].include?("country"), "The scoring fixture requires the country category")
  answers = { "country" => { "A" => "Austria", "B" => "Belgium" }.fetch(replay.state[:letter]) }
  status, plan = game.action_for(surface_action("answer_sheet", "submit", "answers" => answers), replay, answerer, context: context)
  raise "submission failed" if status != :ok
  append_plan(events, plan, answerer, now: context.now)
  replay = game.replay(session, events, repository)

  action = game.automatic_action(replay, owner, context: context)
  status, plan = game.action_for(action, replay, owner, context: context)
  raise "answer closing failed" if status != :ok
  append_plan(events, plan, owner, now: context.now)
  replay = game.replay(session, events, repository)

  action = game.automatic_action(replay, answerer, context: context)
  status, plan = game.action_for(action, replay, answerer, context: context)
  raise "reveal failed" if status != :ok
  append_plan(events, plan, answerer, now: context.now)
  replay = game.replay(session, events, repository)

  action = game.automatic_action(replay, owner, context: context)
  status, plan = game.action_for(action, replay, owner, context: context)
  raise "review start failed" if status != :ok
  append_plan(events, plan, owner, now: context.now)
  replay = game.replay(session, events, repository)

  item = replay.state[:active_players].empty? ? nil : game.surface_spec(replay, judge)
  item = item.parts.first.surface if item.is_a?(GameSurfaces::CompositeSpec)
  review_item = item.items.first
  decisions = { review_item.id => "unique" }
  status, plan = game.action_for(
    surface_action("review", "change", "item_id" => review_item.id, "decision" => "unique"),
    replay,
    judge,
    context: context
  )
  raise "review decision failed" if status != :ok
  append_plan(events, plan, judge, now: context.now)
  replay = game.replay(session, events, repository)

  status, plan = game.action_for(
    surface_action("review", "finish", "decisions" => decisions),
    replay,
    judge,
    context: context
  )
  raise "review finish failed" if status != :ok
  append_plan(events, plan, judge, now: context.now)
  replay = game.replay(session, events, repository)

  action = game.automatic_action(replay, owner, context: context)
  status, plan = game.action_for(action, replay, owner, context: context)
  raise "round scoring failed" if status != :ok
  append_plan(events, plan, owner, now: context.now)
  game.replay(session, events, repository)
end
