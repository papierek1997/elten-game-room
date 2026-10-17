require_relative "elten_array_shuffle"
require_relative "assertions"
require "json"
require_relative "../../games/catalog"
require_relative "../../lib/game_random"

module GameRoomTest
  # A Bridge table driven through the ordinary action_for/replay path.
  class BridgeTable
    Repository = Struct.new(:players) do
      def players_for(_session) = players
      def actor_of(event, _session = nil) = event.fetch("actor")
      def event_id(event) = event.fetch("id")
      def session_id(_session) = 7
    end

    attr_reader :game, :session, :repository, :events, :replay

    def initialize(players = %w[Alice Bob Carol Dave], options = {}, seed: 1)
      @game = GameRoomGames::CATALOG.build("bridge")
      @session = { "options" => JSON.generate(@game.normalize_options(options)) }
      @repository = Repository.new(players)
      @events = []
      @random = GameRoomRandom::SeededSource.new(seed)
      refresh
      deal
    end

    def state = @replay.state

    def context
      GameRoomGames::ActionContext.new(session_id: 7, random_source: @random, now: @events.length)
    end

    def refresh
      @replay = @game.replay(@session, @events, @repository)
    end

    def act(actor, selection)
      status, plan = @game.action_for(selection, @replay, actor, context: context)
      return status unless status == :ok

      plan.events.each do |command|
        @events << { "id" => @events.length + 1, "actor" => actor, "action" => command.action, "value" => command.value }
      end
      refresh
      :ok
    end

    def deal
      owner = @replay.players.first
      selection = @game.automatic_action(@replay, owner, context: context)
      act(owner, selection) if selection
    end

    def seat_player(seat) = state[:seats][seat]

    def call(value)
      act(state[:current_player], { "kind" => "command", "action" => "call", "call" => value })
    end

    def calls(*values)
      values.each { |value| raise "call #{value} rejected" unless call(value) == :ok }
    end

    def play(card, actor: state[:current_player], zone: nil)
      zone ||= state[:seat_to_play] == @game.send(:seat_of, state, actor) ? "hand" : "dummy"
      act(actor, { "kind" => "card", "action" => "select", "zone" => zone, "card" => card })
    end

    def play_lowest_legal
      action = @game.legal_actions(@replay, state[:current_player]).min_by { |item| GameRoomGames::BridgeRules.rank_index(item["card"]) }
      raise "no legal card" unless action

      act(state[:current_player], action)
    end
  end
end
