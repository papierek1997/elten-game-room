require_relative "../../games/dice_poker"

module DiceGamesSupport
  Repository = Struct.new(:players) do
    def players_for(_session); players; end
    def actor_of(event, _session = nil); event.fetch("actor"); end
    def event_id(event); event.fetch("id"); end
  end
  def check(value, message); raise message unless value; end
  def dice_event(id, actor, action, value)
    {"id" => id, "sequence" => id, "actor" => actor, "action" => action, "value" => value, "created_at" => id}
  end
  def dice_session(game, **options)
    {"__id" => 19, "options" => JSON.generate(game.normalize_options(options.transform_keys(&:to_s)))}
  end
end
