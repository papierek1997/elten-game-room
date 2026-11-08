module BlackjackChecksSupport
  Repository = Struct.new(:players) do
    def players_for(_session); players; end
    def actor_of(event, _session = nil); event.fetch("actor"); end
    def event_id(event); event.fetch("id"); end
  end

  class FixedDeck < GameRoomGames::Blackjack
    attr_accessor :first_cards
    protected
    def shuffled_cards(cards, seed)
      ordered = first_cards.map { |card| "0:#{card}" }
      raise "Duplicate fixture card" unless ordered.uniq == ordered
      ordered + super.reject { |card| ordered.include?(card) }
    end
  end

  module_function
  def check(condition, message); raise message unless condition; end
  def event(id, actor, action, value = "")
    {"id" => id, "actor" => actor, "action" => action, "value" => value}
  end
end
