require_relative "base"
require_relative "base/round_tournament"
require_relative "../lib/game_bots"
require_relative "../lib/liars_dice_secrets"

module GameRoomGames
  using GameRoomLocalization::Translations

  class LiarsDice < Base
    include PublicHistoryAnnouncements
    include HiddenSubmissions::Cleanup
    include RoundTournament
    GameRoomServerRandom.register("liars_dice", ["deal"])

    def id; "liars_dice"; end
    def name; _("Liar's dice"); end
    def short_description; _("Bid on everyone's hidden dice, raise the claim or call a bluff. Keep your last die to win."); end
    def minimum_players; 2; end
    def maximum_players; 8; end
    def supports_bots?; true; end
    def player_spatial_audio?; true; end
    def table_sound_event?(event); event["action"] == "deal"; end
    def bot_strategy; @bot_strategy ||= GameRoomBots::HeuristicStrategy.new; end
    def rule_sections; generated_rule_sections; end
    def notification_option_keys(_options); %w[variant]; end

    def option_definitions
      [OptionDefinition.new(key: "variant", label: _("Variant"), kind: :choice, default: "rdr", choices: [
        OptionChoice.new(value: "rdr", label: _("Red Dead style: no wilds, exact calls")),
        OptionChoice.new(value: "classic", label: _("Classic: no wilds, bluff challenges only")),
        OptionChoice.new(value: "perudo", label: _("Perudo: wild ones and special bidding"))]),
        OptionDefinition.new(key: "starting_dice", label: _("Starting dice per player (1-5)"), kind: :integer, default: 5),
        OptionDefinition.new(key: "palifico", label: _("Palifico when a player first reaches one die"), kind: :boolean, default: true, visible_if: {"variant"=>"perudo"}),
        OptionDefinition.new(key: "calza", label: _("Calza: exact calls can recover a die"), kind: :boolean, default: false, visible_if: {"variant"=>"perudo"})]
    end

    def options_error(options, player_count: nil)
      count = normalize_options(options)["starting_dice"]
      _("Choose from 1 to 5 starting dice.") unless count.is_a?(Integer) && count.between?(1,5)
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session["options"])
      state = {players: players, options: options, session_id: (session["__id"] || session["id"]).to_i,
        round: 1, phase: :committing, counts: players.to_h { |player| [player, options["starting_dice"]] },
        commits: {}, seed: nil, reveals: {}, bid: nil, bid_index: 0, challenge: nil, starter: players.first,
        current_player: players.first, palifico: false, palifico_used: [], last_loser: players.first,
        winner: nil, draw: false}
      enable_round_tournament(state, session)
      HiddenSubmissions::Cleanup.start(state, session)
      accepted, history, seen = [], [starting_history(players)], {}
      events.each do |event|
        break if state[:phase] == :finished
        event_id = repository.event_id(event)
        next if seen[event_id]
        actor = players.find { |player| same_user?(player, repository.actor_of(event, session)) }
        if event["action"] == "tournament_elimination"
          next unless apply_round_tournament_elimination(state, event, event_id, history) { restart_after_departure(state) }
        else
          next unless actor && apply_event(state, event, actor, event_id, history)
        end
        accepted << event
        seen[event_id] = true
      end
      Replay.new(players: players, current_player: state[:current_player], state: state, board: nil,
        winner: state[:winner], draw: state[:draw], history: history, accepted_events: accepted)
    end

    def active_actors(replay)
      return [] if replay.finished?
      state = replay.state
      case state[:phase]
      when :committing then alive(state) - state[:commits].keys
      when :revealing then alive(state) - state[:reveals].keys
      when :bidding
        optional = if state[:options]["variant"] == "perudo" && state[:options]["calza"]
          # The normal bot runner acts on the first pending bot. An optional
          # call would be its only choice out of turn, even on an impossible bid.
          alive(state).select { |player| !GameRoomParticipants.bot?(player) && exact_allowed?(state, player) }
        else
          []
        end
        ([state[:current_player]] + optional).uniq
      else []
      end
    end

    def required_decision_key(replay, viewer)
      return nil unless replay && replay.state[:phase] == :bidding && same_user?(replay.current_player, viewer)
      [replay.state[:round], replay.state[:bid_index], viewer.to_s.downcase]
    end

    def concurrent_session_input?(before, after, selection)
      phase = before.state[:phase]
      before.state[:round] == after.state[:round] && phase == after.state[:phase] &&
        ((phase == :committing && selection["action"] == "commit") || (phase == :revealing && selection["action"] == "reveal"))
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished?
      state = replay.state
      return {"kind"=>"command", "action"=>"deal"} if state[:phase] == :dealing && same_user?(actor, replay.players.first)
      player = player_key(state, actor)
      return nil unless active_actors(replay).include?(player)
      action = {committing: "commit", revealing: "reveal"}[state[:phase]]
      {"kind"=>"command", "action"=>action} if action
    end

    def automatic_action_allowed?(replay, actor, table_owner:)
      same_user?(actor, table_owner) || ([:committing, :revealing].include?(replay.state[:phase]) && GameRoomParticipants.includes?(active_actors(replay), actor))
    end

    def automatic_actor(replay, viewer, table_owner:)
      return super if replay.state[:phase] == :dealing
      player_key(replay.state, viewer)
    end

    def legal_actions(replay, actor, context: nil)
      return [] unless GameRoomParticipants.includes?(active_actors(replay), actor)
      state = replay.state
      action = {committing: "commit", revealing: "reveal"}[state[:phase]]
      return [{"kind"=>"command", "action"=>action}] if action
      return exact_allowed?(state, actor) ? [selection(state, "exact")] : [] unless same_user?(state[:current_player], actor)
      actions = []
      1.upto(state[:counts].values.sum) do |quantity|
        1.upto(6) { |face| actions << selection(state, "bid").merge("quantity"=>quantity, "face"=>face) if bid_allowed?(state, quantity, face, actor) }
      end
      actions << selection(state, "challenge") if state[:bid]
      actions << selection(state, "exact") if exact_allowed?(state, actor)
      actions
    end

    def action_for(input, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      state, action = replay.state, input["action"]
      player = player_key(state, actor)
      if action == "deal"
        return [:not_your_turn, nil] unless same_user?(actor, replay.players.first) && state[:phase] == :dealing
        return [:invalid, nil] unless context&.random_source
        template = "#{state[:round]}:{seed}"
        return [:ok, server_seed_plan("deal", template: template)] if context.server_random
        seed = context.random_source.roll(count: 16, sides: 256).values.map { |value| (value - 1).to_s(16).rjust(2,"0") }.join
        return [:ok, event_plan("deal", "#{state[:round]}:#{seed}")]
      end
      return [:not_your_turn, nil] unless player && active_actors(replay).include?(player)
      if action == "commit" && state[:phase] == :committing
        envelope = GameRoomLiarsDiceSecrets.envelope(state, player, context, create: true)
        return [:private_data_missing, nil] unless envelope
        return [:ok, event_plan("commit", "#{state[:round]}:#{GameRoomLiarsDiceSecrets.encode(envelope.commitment)}")]
      elsif action == "reveal" && state[:phase] == :revealing
        envelope = GameRoomLiarsDiceSecrets.envelope(state, player, context)
        return [:private_data_missing, nil] unless envelope
        return [:ok, event_plan("reveal", "#{state[:round]}:#{GameRoomLiarsDiceSecrets.encode(envelope.payload['seed'] + envelope.nonce)}")]
      end
      return [:invalid, nil] unless state[:phase] == :bidding && input["round"] == state[:round] && input["bid_index"] == state[:bid_index]
      return [:not_your_turn, nil] unless same_user?(state[:current_player], actor) || (action == "exact" && state[:options]["variant"] == "perudo")
      if action == "bid"
        quantity = input["quantity"]
        quantity = quantity.to_i if quantity.is_a?(String) && quantity.match?(/\A[1-9][0-9]?\z/)
        return [:invalid_bid, nil] unless bid_allowed?(state, quantity, input["face"], player)
        return [:ok, event_plan("bid", "#{state[:round]}:#{state[:bid_index]}:#{quantity}:#{input['face']}")]
      end
      return [:invalid, nil] unless (action == "challenge" && state[:bid]) || (action == "exact" && exact_allowed?(state, player))
      [:ok, event_plan(action, "#{state[:round]}:#{state[:bid_index]}")]
    rescue HiddenSubmissions::StorageError
      [:local_storage_unavailable, nil]
    end

    def controller_change_phase_error(replay)
      _("The current game contains private data that cannot be transferred at this stage.") if replay && !replay.finished? && replay.state[:commits].any?
    end

    def participant_replacement_error(replay, player:, replacement: nil)
      return nil unless replay && !replay.finished?
      person = player_key(replay.state, player)
      controller_change_phase_error(replay) if person && replay.state[:commits].key?(person) && !replay.state[:reveals].key?(person)
    end

    def save_game_error(replay)
      super || controller_change_phase_error(replay)
    end

    def eliminated_from_game?(replay, viewer)
      player = player_key(replay.state, viewer)
      player != nil && replay.state[:counts][player] == 0
    end

    def tournament_placement_scores(replay, options:)
      state = replay.state
      knockouts = state.fetch(:knockouts, {})
      scores = state[:players].to_h { |player| [player, knockouts.fetch(player, state[:round])] }
      {scores: scores, order: 'higher'}
    end

    def participant_status(replay, participant, connected: true)
      player = player_key(replay.state, participant)
      return super unless player
      _("Dice remaining: %{count}") % {count: replay.state[:counts][player]}
    end

    def turn_announcement(replay, viewer)
      super if replay&.state&.[](:phase) == :bidding
    end

    def turn_transition_history_entry(before_replay, after_replay, event_id:)
      super if after_replay&.state&.[](:phase) == :bidding
    end

    def move_error(status)
      return _("Raise the previous bid according to this variant and the total dice in play.") if status == :invalid_bid
      return _("Your private dice secret is unavailable. Return using the same Elten profile.") if status == :private_data_missing
      super
    end

    private

    def player_key(state, actor); state[:players].find { |player| same_user?(player, actor) }; end
    def alive(state); tournament_contenders(state); end
    def tournament_inactive_players(state); state[:players].select { |player| state[:counts][player].zero? }; end
    def tournament_round_scores(state); state[:counts]; end

    def restart_after_departure(state)
      # Do not require a departed player's secret, or reuse commitments after
      # the server seed was published. Only the unsettled round is discarded.
      HiddenSubmissions::Cleanup.confirm(state, GameRoomLiarsDiceSecrets.round_id(state), state[:commits])
      state[:tournament_eliminations].last.each { |player| state[:counts][player] = 0 }
      starter = state[:counts][state[:starter]].positive? ? state[:starter] : next_alive(state, state[:starter])
      last_loser = state[:counts][state[:last_loser]].positive? ? state[:last_loser] : starter
      state.merge!(round: state[:round] + 1, phase: :committing, current_player: alive(state).first,
        starter: starter, last_loser: last_loser, commits: {}, reveals: {}, seed: nil, bid: nil,
        bid_index: 0, challenge: nil, palifico: state[:palifico] && starter == state[:starter] && alive(state).size > 2)
    end
    def selection(state, action); {"kind"=>"command", "action"=>action, "round"=>state[:round], "bid_index"=>state[:bid_index]}; end
    def bid_allowed?(state, quantity, face, actor)
      GameRoomLiarsDiceRules.raise_allowed?(quantity, face, state[:bid], variant: state[:options]["variant"],
        total: state[:counts].values.sum, palifico: state[:palifico], may_change: state[:palifico_used].include?(actor))
    end
    def exact_allowed?(state, actor)
      state[:bid] && (state[:options]["variant"] == "rdr" || (state[:options]["variant"] == "perudo" && state[:options]["calza"] && actor != state[:bid][:actor]))
    end

    def history_entry(history, event_id, actor, kind, text)
      history << HistoryEntry.new(key: "#{kind}:#{event_id}:#{history.size}", event_id: event_id, actor: actor, kind: kind, text: text)
    end

    def apply_event(state, event, actor, event_id, history)
      action, value = event.values_at("action", "value")
      if action == "commit"
        return false unless state[:phase] == :committing && alive(state).include?(actor) && !state[:commits].key?(actor)
        prefix, body = value.to_s.split(":", 2)
        digest = GameRoomLiarsDiceSecrets.decode(body)
        return false unless prefix == state[:round].to_s && digest && !state[:commits].value?(digest)
        state[:commits][actor] = digest
        if state[:commits].size == alive(state).size
          state[:phase], state[:current_player] = :dealing, state[:players].first
        else
          state[:current_player] = (alive(state) - state[:commits].keys).first
        end
      elsif action == "deal"
        return false unless state[:phase] == :dealing && actor == state[:players].first
        seed = GameRoomServerRandom.text_seed_value(event, template: "#{state[:round]}:{seed}")
        return false unless seed
        state.merge!(seed: seed, phase: :bidding, current_player: state[:starter])
        text = _("Round %{round}. The dice are ready.") % {round: state[:round]}
        text += " " + _("Palifico: ones are not wild.") if state[:palifico]
        history_entry(history, event_id, "", :dice_ready, text)
      elsif action == "reveal"
        return apply_reveal(state, event, actor, event_id, history)
      else
        return false unless state[:phase] == :bidding
        if action == "exact" && state[:options]["variant"] == "perudo"
          return false unless alive(state).include?(actor) && exact_allowed?(state, actor)
        else
          return false unless actor == state[:current_player]
        end
        parts = value.to_s.split(":", -1)
        return false unless parts.shift == state[:round].to_s && parts.shift == state[:bid_index].to_s
        if action == "bid"
          return false unless parts.size == 2 && parts.all? { |part| part.match?(/\A[1-9][0-9]*\z/) }
          quantity, face = parts.map(&:to_i)
          return false unless bid_allowed?(state, quantity, face, actor)
          state[:bid] = {quantity: quantity, face: face, actor: actor}
          state[:bid_index] += 1
          state[:current_player] = next_alive(state, actor)
          history_entry(history, event_id, actor, :bid, _("%{player} bids %{quantity} dice showing %{face}.") % {player: participant_name(actor), quantity: quantity, face: face})
        elsif parts.empty? && ((action == "challenge" && state[:bid]) || (action == "exact" && exact_allowed?(state, actor)))
          state.merge!(phase: :revealing, challenge: {actor: actor, exact: action == "exact"}, current_player: alive(state).first)
          player = participant_name(actor)
          text = if action == "exact"
            _("%{player} says the bid is exact.") % {player: player}
          else
            _("%{player} challenges the bid.") % {player: player}
          end
          history_entry(history, event_id, actor, :challenge, text)
        else
          return false
        end
      end
      true
    end

    def apply_reveal(state, event, actor, event_id, history)
      return false unless state[:phase] == :revealing && alive(state).include?(actor) && !state[:reveals].key?(actor)
      prefix, body = event["value"].to_s.split(":", 2)
      secret = GameRoomLiarsDiceSecrets.decode(body)
      return false unless prefix == state[:round].to_s && secret
      seed, nonce = secret[0,32], secret[32,32]
      return false unless HiddenSubmissions::Commitment.valid?(payload: GameRoomLiarsDiceSecrets.payload(state, actor, seed), nonce: nonce, commitment: state[:commits][actor])
      dice = GameRoomLiarsDiceRules.dice(state[:seed], seed, state[:counts][actor])
      state[:reveals][actor] = dice
      HiddenSubmissions::Cleanup.confirm(state, GameRoomLiarsDiceSecrets.round_id(state), actor=>state[:commits][actor])
      history_entry(history, event_id, actor, :reveal, _("%{player} reveals %{dice}.") % {player: participant_name(actor), dice: dice.join(", ")})
      if state[:reveals].size == alive(state).size
        settle_round(state, event_id, history)
      else
        state[:current_player] = (alive(state) - state[:reveals].keys).first
      end
      true
    end

    def next_alive(state, player)
      index = state[:players].index(player)
      1.upto(state[:players].size).map { |offset| state[:players][(index + offset) % state[:players].size] }.find { |person| state[:counts][person] > 0 }
    end

    def settle_round(state, event_id, history)
      caller, exact = state[:challenge].values_at(:actor, :exact)
      count = GameRoomLiarsDiceRules.count(state[:reveals].values.flatten, state[:bid][:face], variant: state[:options]["variant"], palifico: state[:palifico])
      correct = exact ? count == state[:bid][:quantity] : count < state[:bid][:quantity]
      history_entry(history, event_id, "", :count, _("Actual count for face %{face}: %{count}.") % {face: state[:bid][:face], count: count})
      losers = if exact && correct
        if state[:options]["variant"] == "rdr"
          alive(state) - [caller]
        else
          room = state[:counts][caller] < state[:options]["starting_dice"]
          state[:counts][caller] += 1 if room
          text = room ? _("%{player} was right and gets one die back.") : _("%{player} was right and already has all their dice.")
          history_entry(history, event_id, caller, :calza, text % {player: participant_name(caller)})
          []
        end
      else
        [exact || !correct ? caller : state[:bid][:actor]]
      end
      losers.each do |player|
        state[:counts][player] -= 1
        (state[:knockouts] ||= {})[player] = state[:round] if state[:round_tournament] && state[:counts][player].zero?
        history_entry(history, event_id, player, :lost_die, _("%{player} loses a die; %{count} remain.") % {player: participant_name(player), count: state[:counts][player]})
      end
      record_tournament_round(state, event_id)
      if alive(state).one?
        state.merge!(phase: :finished, winner: alive(state).first, current_player: nil)
        history << result_history(event_id: event_id, winner: state[:winner], draw: false)
        return
      end
      state[:last_loser] = losers.first if losers.any?
      starter = losers.first || state[:last_loser]
      starter = caller if exact && correct && state[:options]["variant"] == "rdr"
      starter = next_alive(state, starter) if state[:counts][starter] == 0
      palifico = state[:options]["variant"] == "perudo" && state[:options]["palifico"] && alive(state).size > 2 &&
        losers.include?(starter) && state[:counts][starter] == 1 && !state[:palifico_used].include?(starter)
      state[:palifico_used] << starter if palifico
      state.merge!(round: state[:round] + 1, phase: :committing, starter: starter, current_player: alive(state).first,
        commits: {}, reveals: {}, seed: nil, bid: nil, bid_index: 0, challenge: nil, palifico: !!palifico)
    end
  end
end

require_relative "liars_dice_players"
require_relative "generated/rulebooks/liars_dice"
