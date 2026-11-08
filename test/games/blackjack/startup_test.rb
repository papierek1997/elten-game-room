require_relative "../../../games/blackjack" unless defined?(GameRoomGames::Blackjack)
require_relative "../../../lib/game_event_presenter" unless defined?(GameRoomEventPresenter)

module BlackjackStartupChecks
  Repository = Struct.new(:players) do
    def players_for(_session); players; end
    def actor_of(event, _session = nil); event.fetch("actor"); end
    def event_id(event); event.fetch("id"); end
  end

  class QuietProgram
    def self.normalized_settings; {"background_turn_sound" => false}; end
  end

  def self.run!
    game = GameRoomGames::Blackjack.new
    repository = Repository.new(%w[Alice Bob])
    session = {"options" => JSON.generate(game.default_options)}
    initial = game.replay(session, [], repository)
    raise "Initial automatic phase requested a decision" unless game.required_decision_key(initial, "Alice").nil?
    events = [{"id" => 1, "actor" => "Alice", "action" => "deal", "value" => "1|#{'0' * 32}"}]
    replay = game.replay(session, events, repository)
    raise "Fixture does not reach a player decision" unless replay.state[:phase] == :playing
    actor = replay.current_player
    raise "Active player has no decision" unless game.required_decision_key(replay, actor)
    presenter = GameRoomEventPresenter.new(game: -> { game }, repository: -> { repository },
      program: -> { QuietProgram.new }, viewer: -> { actor }, client: -> {}, surface_state: -> { {} },
      clock: -> { 0 }, covered: -> { false }, speech: ->(_text) {}, trace: ->(*_args) {},
      history_changed: -> {}, session_changed: -> {})
    presenter.__send__(:present_required_decision, nil, replay)
    raise "Missing replay must not request a decision" unless game.required_decision_key(nil, actor).nil?
    puts "Blackjack startup: real first decision accepts a missing previous replay"
    true
  end
end

BlackjackStartupChecks.run! if $PROGRAM_NAME == __FILE__
