def _(text)
  text
end

def n_(singular, plural, count)
  count == 1 ? singular : plural
end

require "json"
require_relative "sequence_random"
require_relative "../../games/mille_bornes"

module MilleBornesTest
  class Repository
    def initialize(players)
      @players = players
    end

    def players_for(session)
      session.fetch("__players", @players)
    end

    def actor_of(event, _session = nil)
      event.fetch("actor")
    end

    def event_id(event)
      event.fetch("id")
    end
  end

  class Fixture
    attr_reader :game, :players, :repository, :session, :events, :context

    def initialize(players: %w[Alice Bob Carol], options: {})
      @game = GameRoomGames::MilleBornes.new
      @players = players
      @repository = Repository.new(players)
      @session = { "id" => 17, "options" => JSON.generate(game.normalize_options(options)) }
      @events = []
      @context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SequenceSource.new(Array.new(160, 17)))
    end

    def replay
      game.replay(session, events, repository)
    end

    def start
      act(players.first, { "kind" => "command", "action" => "deal" })
    end

    def act(actor, selection)
      status, plan = game.action_for(selection, replay, actor, context: context)
      MilleBornesTest.assert(status == :ok, "action rejected: #{actor} #{selection}: #{status}")
      plan.events.each do |command|
        events << MilleBornesTest.event(events.length + 1, actor, command.action, command.value)
      end
      result = replay
      MilleBornesTest.assert(result.accepted_events.length == events.length, "plan was rejected by replay")
      result
    end

    def scenario
      start if events.empty?
      state = Marshal.load(Marshal.dump(replay.state))
      state[:draw_pile] = %w[25:8 25:9 25:10 50:8 50:9 50:10]
      state[:hands] = players.to_h { |player| [player, %w[75:1 100:1]] }
      state[:phase] = :playing
      state[:current_player] = players.first
      state
    end

    def play(state, actor, action, card = nil, **details)
      selection = { "kind" => card ? "card" : "command", "action" => action }
      selection["card"] = card if card
      details.each { |key, value| selection[key.to_s] = value }
      current = snapshot(state)
      status, plan = game.action_for(selection, current, actor, context: context)
      return status unless status == :ok
      plan.events.each do |command|
        accepted = game.send(:apply_event, state, MilleBornesTest.event(100 + state[:action_number], actor, command.action, command.value),
          actor, 100 + state[:action_number], [])
        MilleBornesTest.assert(accepted, "action_for/replay disagree: #{selection}")
      end
      status
    end

    def snapshot(state)
      result = GameRoomGames::MilleBornes::SessionReplay.new(players: players, state: state, history: [], accepted_events: [],
        current_player: state[:current_player], winner: state[:winner], draw: state[:draw])
      result.session_identity = session["id"]
      result
    end
  end

  module_function

  def assert(condition, message)
    raise message unless condition
  end

  def equal(expected, actual, message)
    raise "#{message}: expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
  end

  def event(identifier, actor, action, value = "")
    { "id" => identifier, "actor" => actor, "action" => action, "value" => value }
  end

  def test(name)
    yield
    puts "PASS #{name}"
  end
end
