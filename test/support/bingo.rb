require_relative "../../games/bingo"

module BingoChecksSupport
  Repository = Struct.new(:players) do
    def players_for(_session); players; end
    def actor_of(event, _session = nil); event.fetch("actor"); end
    def event_id(event); event.fetch("id"); end
  end

  def check(value, message); raise message unless value; end
  def bingo_event(id, actor, action, value = "", time: 100)
    {"id" => id, "sequence" => id, "actor" => actor, "action" => action, "value" => value, "created_at" => time}
  end
  def bingo_session(game, **options)
    {"__id" => 1, "options" => JSON.generate(game.normalize_options(options.transform_keys(&:to_s)))}
  end
end
