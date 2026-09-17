def _(text)
  text
end

def n_(singular, plural, count)
  count.to_i == 1 ? singular : plural
end

module GameSurfaces
  Action = Struct.new(:kind, :name, :payload, :source, keyword_init: true)
  CardChoice = Struct.new(:id, :label, :value, keyword_init: true)
  Card = Struct.new(:id, :label, :value, :choices, :shift_choice, :choice_header, :sort_keys, keyword_init: true)
  CardZoneSpec = Struct.new(:id, :header, :cards, :empty_label, :hand_order, :hand_epoch, keyword_init: true)
  CardTableSpec = Struct.new(:zones, keyword_init: true)
  Command = Struct.new(:id, :label, :enabled, :payload, keyword_init: true)
  CommandPanelSpec = Struct.new(:commands, keyword_init: true)
  PawnTrackItem = Struct.new(:id, :label, :action, keyword_init: true)
  PawnTrackSpec = Struct.new(:id, :header, :items, :empty_label, :activation_action, :menus, keyword_init: true)
  Die = Struct.new(:id, :value, :sides, :held, :label, :enabled, keyword_init: true)
  ScoreChoice = Struct.new(:id, :label, :value, keyword_init: true)
  RollAndScoreSpec = Struct.new(:id, :header, :dice, :categories, :can_roll, :force_categories, :empty_label, :roll_number, keyword_init: true)
  PacketCardSpec = Struct.new(:id, :header, :cards, :action_name, :allow_packet, :empty_label, :hand_order, :hand_epoch, keyword_init: true)
  SurfacePart = Struct.new(:id, :surface, keyword_init: true)
  CompositeSpec = Struct.new(:parts, keyword_init: true)
end

require "json"
require_relative "../../lib/game_random"
require_relative "../../games/base"
require_relative "../../games/card_game"
require_relative "../../content/monopoly_boards"
require_relative "../../games/monopoly"
require_relative "../../games/yahtzee"
require_relative "../../games/uno"
require_relative "../../games/poker"
require_relative "../../games/makao"
require_relative "../../games/biblios"

class NewGames116Repository
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

class NewGames116Random
  Roll = Struct.new(:values, keyword_init: true)

  def initialize
    @value = 0
  end

  def roll(count:, sides:)
    values = Array.new(count) do
      @value += 1
      ((@value - 1) % sides.to_i) + 1
    end
    Roll.new(values: values)
  end
end

def assert(condition, message)
  raise message if !condition
end

def context_for(random = NewGames116Random.new)
  GameRoomGames::ActionContext.new(random_source: random, now: 1_800_000_000)
end

def append_action(game, session, repository, events, replay, actor, selection, context = nil)
  status, plan = game.action_for(selection, replay, actor, context: context)
  raise "#{game.id} rejected #{selection.inspect}: #{status}" if status != :ok
  plan.events.each do |command|
    events << { "id" => events.length + 1, "actor" => actor, "action" => command.action, "value" => command.value }
  end
  game.replay(session, events, repository)
end
