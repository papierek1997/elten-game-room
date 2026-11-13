require 'json'
require_relative 'assertions'
require_relative '../../lib/game_surfaces/specifications'
require_relative '../../games/billiards'

def _(value); value; end

module BilliardsFixture
  class Repository
    attr_accessor :players
    def initialize(players); @players = players; end
    def players_for(_session); @players; end
    def actor_of(event, _session = nil); event.fetch('actor'); end
    def event_id(event); event.fetch('id'); end
  end

  class Match
    include GameRoomTest::Assertions
    attr_reader :game, :session, :repository, :events
    def initialize(players: ['Alice'], options: {})
      @game = GameRoomGames::Billiards.new
      @session = {'__id'=>'billiards-test', 'options'=>JSON.generate(game.normalize_options(options))}
      @repository = Repository.new(players)
      @events = []
    end
    def replay; game.replay(session, events, repository); end
    def selection(action, payload = {}); {'kind'=>'billiards', 'action'=>action, 'revision'=>replay.state[:revision]}.merge(payload); end
    def submit(action, payload = {}, actor: replay.current_player)
      value = selection(action, payload)
      status, plan = game.action_for(value, replay, actor)
      assert_equal(:ok, status, "Rejected #{value.inspect}")
      plan.events.each { |e| events << {'id'=>events.size + 1, 'actor'=>actor, 'action'=>e.action, 'value'=>e.value} }
      replay
    end
    def shot; {'angle'=>0, 'power'=>200, 'top'=>0, 'side'=>0}; end
  end
end
