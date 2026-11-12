require_relative "base"
require_relative "base/round_tournament"
require_relative "../lib/game_bots"
require_relative "../lib/blackjack_auction"
require_relative "../lib/twenty_one_strategy"

module GameRoomGames
  using GameRoomLocalization::Translations

  class BlackjackDice < Base
    include PublicHistoryAnnouncements
    include BlackjackAuction
    include RoundTournament
    GameRoomServerRandom.register("blackjack_dice", ["roll"])

    def id; "blackjack_dice"; end
    def name; _("Blackjack Dice"); end
    def short_description; _("Roll towards 21, stop before going bust and outscore the other players."); end
    def minimum_players; 2; end
    def maximum_players; 8; end
    def supports_bots?; true; end
    def bot_strategy; @bot_strategy ||= GameRoomBots::HeuristicStrategy.new; end
    def rule_sections; generated_rule_sections; end
    def player_spatial_audio?; true; end

    def option_definitions
      [
        OptionDefinition.new(key: "variant", label: _("Variant"), kind: :choice, default: "two_dice", choices: [
          OptionChoice.new(value: "two_dice", label: _("Two dice, then one from 16")),
          OptionChoice.new(value: "one_die", label: _("One die throughout"))
        ]),
        OptionDefinition.new(key: "score_limit", label: _("Score limit"), kind: :integer, default: 10, visible_if: ->(options) { !chip_game?(options) }),
        OptionDefinition.new(key: "scoring", label: _("Round settlement"), kind: :choice, default: "points", choices: [
          OptionChoice.new(value: "points", label: _("Match points")),
          OptionChoice.new(value: "chips", label: _("Virtual chips"))
        ]),
        OptionDefinition.new(key: "starting_chips", label: _("Starting chips"), kind: :integer, default: 100, visible_if: {"scoring" => "chips"}),
        OptionDefinition.new(key: "stake", label: _("Opening contribution"), kind: :integer, default: 10, visible_if: {"scoring" => "chips"}),
        OptionDefinition.new(key: "round_limit", label: _("Number of rounds"), kind: :integer, default: 10, visible_if: {"scoring" => "chips"})
      ]
    end

    def normalize_options(values)
      result = super
      # Omit inactive settings without changing historical point-game options.
      inactive = chip_game?(result) ? %w[score_limit] : %w[scoring starting_chips stake round_limit]
      if chip_game?(result) && (values.key?("blackjack_betting_version") || values.key?(:blackjack_betting_version))
        version = values.fetch("blackjack_betting_version") { values[:blackjack_betting_version] }
        result["blackjack_betting_version"] = GameRoomOptionValues.integer_value(version)
      end
      result.reject { |key, _| inactive.include?(key) }
    end

    def effective_option_definitions(options = {})
      betting_version_definitions(super, options)
    end

    def new_game_options(values)
      result = normalize_options(values)
      chip_game?(result) ? result.merge("blackjack_betting_version" => 2) : result
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _("This blackjack betting version is not supported.") if values.key?("blackjack_betting_version") && values["blackjack_betting_version"] != 2
      return _("Choose a supported blackjack variant.") unless %w[two_dice one_die].include?(values["variant"])
      unless chip_game?(values)
        return _("The score limit must be from 1 to 100.") unless values["score_limit"].is_a?(Integer) && values["score_limit"].between?(1, 100)
      end
      if chip_game?(values)
        return _("Starting chips must be from 10 to 10000.") unless values["starting_chips"].is_a?(Integer) && values["starting_chips"].between?(10, 10_000)
        return _("The stake must be positive and cannot exceed starting chips.") unless values["stake"].is_a?(Integer) && values["stake"].between?(1, values["starting_chips"])
        return _("The number of rounds must be from 1 to 100.") unless values["round_limit"].is_a?(Integer) && values["round_limit"].between?(1, 100)
      end
      nil
    end

    def notification_option_keys(_options); %w[variant score_limit scoring]; end
    def participant_scores(replay); (replay.state[:chips] || replay.state[:scores]).dup; end
    def eliminated_from_game?(replay, viewer)
      super || GameRoomParticipants.includes?(replay&.state&.fetch(:eliminated, []).to_a, viewer)
    end
    def shortcut_features; super + [:scores, :current_total, :last_roll]; end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      case feature.to_sym
      when :scores
        scores = participant_scores(replay)
        {message: state[:players].map { |player| "#{participant_name(player)}: #{scores[player]}" }.join("; ")}
      when :current_total
        return nil unless state[:phase] == :playing
        {message: _("Current total: %{total}") % {total: state[:total]}}
      when :last_roll
        return nil unless state[:phase] == :playing && state[:last_roll].any?
        {message: _("Last roll: %{dice}") % {dice: state[:last_roll].join(", ")}}
      else super
      end
    end

    def dice_count(state)
      state[:options]["variant"] == "two_dice" && state[:total] < 16 ? 2 : 1
    end

    def automatic_action(replay, actor, context: nil)
      {"kind" => "command", "action" => "ante"} if replay.state[:phase] == :awaiting_ante && same_user?(actor, replay.players.first)
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || !same_user?(replay.current_player, actor)
      return auction_actions(replay, actor) if replay.state[:phase] == :betting && auction_rules?(replay.state[:options])
      return [] if replay.state[:phase] == :awaiting_ante
      if replay.state[:phase] == :betting
        maximum = maximum_stake(replay.state)
        return [1, default_stake(replay.state), maximum / 2, maximum].select(&:positive?).uniq.sort.map do |amount|
          {"kind" => "command", "action" => "bet", "amount" => amount}
        end
      end
      actions = [{"kind" => "dice", "action" => "roll"}]
      actions << {"kind" => "dice", "action" => "stand"} if replay.state[:total].positive?
      actions
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      if selection["action"] == "ante"
        return automatic_action(replay, actor) ? [:ok, event_plan("ante", "")] : [:invalid, nil]
      end
      return [:not_your_turn, nil] unless same_user?(replay.current_player, actor)
      return auction_plan(selection, replay) if replay.state[:phase] == :betting && auction_rules?(replay.state[:options])
      action = selection["action"].to_s
      action = selection["card"].to_s if selection["kind"] == "card" && selection["zone"] == "actions" && action == "select"
      if replay.state[:phase] == :betting
        name, preset = action.split(":", 2)
        raw = preset || selection["amount"]
        return [:invalid, nil] unless name == "bet" && valid_stake?(replay.state, raw)
        return [:ok, event_plan("bet", raw.to_s)]
      end
      return [:invalid, nil] unless legal_actions(replay, actor).any? { |item| item["action"] == action }
      return [:ok, event_plan("stand", "")] if action == "stand"
      return [:invalid, nil] unless context&.random_source
      count = dice_count(replay.state)
      if context.server_random
        [:ok, ActionPlan.new(events: [GameRoomServerRandom.command(action: "roll", count: count, sides: 6)])]
      else
        values = context.random_source.roll(count: count, sides: 6).values
        [:ok, event_plan("roll", values.join(","))]
      end
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      return auction_opening_bot_score(state, action) if state[:phase] == :betting && auction_rules?(state[:options])
      return -(action["amount"].to_i - default_stake(state)).abs if state[:phase] == :betting

      two_dice = state[:options]["variant"] == "two_dice"
      chips = chip_game?(state[:options])
      bonus = !chips && state[:scores][actor] + 1 < state[:options]["score_limit"] ? 0.15 : 0.0
      opponent = GameRoomTwentyOneStrategy.dice_opponent(two_dice)
      if chips && auction_rules?(state[:options])
        stand_value, bust_value = GameRoomTwentyOneStrategy.pot_values(auction_pots(state), actor, state[:totals], opponent)
      else
        stand_value = GameRoomTwentyOneStrategy.contest_value(state[:totals].values,
          state[:order].size - state[:totals].size - 1, opponent, split_ties: chips, bonus: bonus)
        bust_value = 0
      end
      plan = GameRoomTwentyOneStrategy::Plan.new(stand_value, bust_value: bust_value, cards: false) { |sum| GameRoomTwentyOneStrategy.dice_weights(two_dice, sum) }
      total = state[:total]
      action["action"] == "stand" ? plan.stand(total, false) + 1e-9 : plan.draw(total, false)
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session["options"])
      if GameRoomTournamentMarker.present?(session) && !options.key?("blackjack_betting_version")
        options = new_game_options(options)
      end
      state = initial_state(players, options)
      enable_round_tournament(state, session)
      accepted, history, seen = [], [starting_history(players)], {}
      events.each do |event|
        break if state[:phase] == :finished
        event_id = repository.event_id(event)
        next if seen[event_id]
        actor = repository.actor_of(event, session)
        action, value = event.values_at("action", "value")
        if action == "tournament_elimination"
          next unless apply_round_tournament_elimination(state, event, event_id, history) { restart_dice_round(state) }
          accepted << event
          seen[event_id] = true
          next
        elsif action == "ante" && auction_rules?(state[:options])
          next unless state[:phase] == :awaiting_ante && same_user?(actor, players.first) && value.to_s.empty?
          start_auction(state, state[:order], event_id, history)
          accepted << event
          seen[event_id] = true
          next
        end
        next unless same_user?(actor, state[:current_player])
        if action == "bet" && auction_rules?(state[:options])
          next unless apply_auction(state, event, actor, event_id, history)
        elsif action == "bet" && state[:phase] == :betting && valid_stake?(state, value)
          apply_stake(state, value.to_i, event_id, history)
        elsif action == "roll" && state[:phase] == :playing
          values = value.to_s.split(",", -1)
          next unless values.size == dice_count(state) && values.all? { |item| item.match?(/\A[1-6]\z/) }
          next unless GameRoomServerRandom.valid_dice_event?(event, count: dice_count(state), sides: 6)
          state[:last_roll] = values.map(&:to_i)
          state[:total] += state[:last_roll].sum
          format = if state[:total] > 21
            _("%{player} rolls %{dice} and goes over 21. Total: %{total}.")
          elsif state[:total] == 21
            _("%{player} rolls %{dice} and stops at %{total}.")
          else
            _("%{player} rolled %{dice}; total %{total}.")
          end
          add_history(history, event_id, state[:current_player], state[:total] > 21 ? :bust : :roll,
            format % {player: participant_name(state[:current_player]), dice: values.join(", "), total: state[:total]})
          finish_turn(state, event_id, history) if state[:total] >= 21
        elsif action == "stand" && state[:phase] == :playing && value.to_s.empty? && state[:total].positive?
          add_history(history, event_id, state[:current_player], :stand,
            _("%{player} stood on %{total}.") % {player: participant_name(state[:current_player]), total: state[:total]})
          finish_turn(state, event_id, history)
        else
          next
        end
        accepted << event
        seen[event_id] = true
      end
      Replay.new(board: nil, players: players, current_player: state[:current_player], winner: state[:winner],
        draw: state[:draw], state: state, accepted_events: accepted, history: history)
    end

    def surface_spec(replay, viewer)
      state = replay.state
      return auction_surface(replay, viewer) if state[:phase] == :betting && auction_rules?(state[:options])
      if state[:phase] == :betting
        actions = legal_actions(replay, viewer).map do |action|
          GameSurfaces::Card.new(id: "bet:#{action['amount']}", value: "bet:#{action['amount']}",
            label: _("Stake %{chips} chips each") % {chips: action["amount"]})
        end
        header = _("Choose the round stake (maximum %{maximum})") % {maximum: maximum_stake(state)}
        return GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(id: "actions", header: header,
          cards: actions, empty_label: current_turn_shortcut_text(replay, viewer))])
      end
      roll_label = dice_count(state) == 1 ? _("Roll one die") : _("Roll %{count} dice") % {count: dice_count(state)}
      labels = {"roll" => roll_label, "stand" => _("Keep your total")}
      actions = legal_actions(replay, viewer).map do |action|
        GameSurfaces::Card.new(id: action["action"], value: action["action"], label: labels.fetch(action["action"]))
      end
      header = _("Round %{round}; current total %{total}") % {round: state[:round], total: state[:total]}
      header += "; " + (_("Pot: %{chips} chips") % {chips: state[:pot]}) if chip_game?(state[:options])
      GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(id: "actions", header: header,
        cards: actions, empty_label: result_text(replay) || current_turn_shortcut_text(replay, viewer))])
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      cues = auction_sound_cues(event, history)
      cues << "roll" if event["action"] == "roll"
      cues << "lose1" if history.any? { |entry| entry.kind == :bust && same_user?(entry.actor, viewer) }
      cues
    end

    def custom_game_shortcuts(replay, viewer)
      if replay.state[:phase] == :playing && same_user?(replay.current_player, viewer)
        return %w[r space].map do |key|
          GameShortcut.new(key: key, label: _("roll the dice"), kind: :action, action_kind: "dice", action_name: "roll")
        end
      end
      return auction_shortcuts(replay, viewer) if replay.state[:phase] == :betting && auction_rules?(replay.state[:options])
      return [] unless replay.state[:phase] == :betting && same_user?(replay.current_player, viewer)
      maximum = maximum_stake(replay.state)
      [GameShortcut.new(key: "b", label: _("set the round stake"), kind: :number_input,
        prompt: _("Round stake (1 to %{maximum})") % {maximum: maximum}, action_kind: "command", action_name: "bet",
        value_key: "amount", allowed_values: 1..maximum, default_value: default_stake(replay.state),
        invalid_message: _("Choose a stake everyone can afford."))]
    end

    private

    def auction_unit; 1; end

    def complete_auction(state, event_id, history)
      state[:order] = auction_contenders(state)
      state.merge!(phase: :playing, current_player: state[:order].first, total: 0, last_roll: [])
      if state[:order].one?
        state[:totals] = {state[:order].first => 0}
        finish_chip_round(state, event_id, history)
      end
    end

    def chip_game?(options); options["scoring"] == "chips"; end

    def tournament_round_scores(state)
      state[:chips] || state[:scores]
    end

    def restart_dice_round(state)
      active = tournament_contenders(state)
      phase = :playing
      if state[:chips]
        if auction_rules?(state[:options])
          refund_interrupted_auction(state)
          phase = :awaiting_ante
        else
          state[:order].each { |player| state[:chips][player] += state[:stake] } if state[:pot].positive?
          state[:pot] = 0
          phase = :betting
        end
        order = active.rotate((state[:round] - 1) % active.size)
      else
        order = state[:players].rotate((state[:round] - 1) % state[:players].size) & active
      end
      state.merge!(phase: phase, order: order, current_player: phase == :awaiting_ante ? state[:players].first : order.first,
        totals: {}, total: 0, last_roll: [])
    end

    def initial_state(players, options)
      state = {players: players, options: options, scores: players.to_h { |player| [player, 0] },
        round: 1, order: players.dup, totals: {}, total: 0, last_roll: [], current_player: players.first,
        phase: :playing, winner: nil, draw: false}
      if chip_game?(options)
        state.merge!(chips: players.to_h { |player| [player, options["starting_chips"]] }, pot: 0, stake: 0,
          eliminated: [], phase: :betting)
        state[:phase] = :awaiting_ante if auction_rules?(options)
      end
      state
    end

    def maximum_stake(state); state[:order].map { |player| state[:chips].fetch(player) }.min; end
    def default_stake(state)
      amount = state[:stake].positive? ? state[:stake] : state[:options]["stake"]
      [amount, maximum_stake(state)].min
    end

    def valid_stake?(state, raw)
      raw.to_s.match?(/\A[1-9][0-9]{0,5}\z/) && raw.to_i.between?(1, maximum_stake(state))
    end

    def apply_stake(state, amount, event_id, history)
      state[:order].each { |player| state[:chips][player] -= amount }
      state.merge!(pot: amount * state[:order].size, stake: amount, phase: :playing)
      add_history(history, event_id, state[:current_player], :stake,
        _("Each player staked %{stake} chips; pot %{pot}.") % {stake: amount, pot: state[:pot]})
    end

    def add_history(history, event_id, actor, kind, text)
      history << HistoryEntry.new(key: "#{kind}:#{event_id}:#{history.size}", event_id: event_id, actor: actor, kind: kind, text: text)
    end

    def finish_turn(state, event_id, history)
      player = state[:current_player]
      state[:totals][player] = state[:total]
      next_index = state[:order].index(player) + 1
      if next_index == state[:order].size
        return finish_chip_round(state, event_id, history) if chip_game?(state[:options])
        valid = state[:totals].select { |_person, total| total <= 21 }
        best = valid.values.max
        winners = valid.keys.select { |person| valid[person] == best }
        if winners.size == 1
          winner = winners.first
          points = best == 21 ? 2 : 1
          state[:scores][winner] += points
          text = n_("%{player} wins the round with %{total} and earns %{points} point.",
            "%{player} wins the round with %{total} and earns %{points} points.", points) %
            {player: participant_name(winner), total: best, points: points}
          add_history(history, event_id, winner, :round, text)
          if state[:scores][winner] >= state[:options]["score_limit"]
            record_tournament_round(state, event_id)
            state.merge!(phase: :finished, current_player: nil, winner: winner)
            history << result_history(event_id: event_id, winner: winner)
            return
          end
        elsif winners.empty?
          add_history(history, event_id, "", :round, _("Everyone went over 21. No points this round."))
        else
          add_history(history, event_id, "", :round,
            _("%{players} tie at %{total}. No points this round.") % {
              players: winners.map { |person| participant_name(person) }.join(", "), total: best})
        end
        record_tournament_round(state, event_id)
        state[:round] += 1
        state[:order] = state[:players].rotate((state[:round] - 1) % state[:players].size) & tournament_contenders(state)
        state[:totals] = {}
        next_index = 0
      end
      state.merge!(current_player: state[:order][next_index], total: 0, last_roll: [])
    end

    def finish_chip_round(state, event_id, history)
      return finish_auction_round(state, event_id, history) if auction_rules?(state[:options])
      valid = state[:totals].select { |_player, total| total <= 21 }
      best = valid.values.max
      winners = state[:order].select { |player| valid[player] == best && valid.key?(player) }
      if winners.empty?
        state[:order].each { |player| state[:chips][player] += state[:stake] }
        text = _("Everyone went bust; all stakes were returned.")
      else
        share, remainder = state[:pot].divmod(winners.size)
        winners.each_with_index { |player, index| state[:chips][player] += share + (index < remainder ? 1 : 0) }
        text = dice_pot_result(winners, state[:pot])
      end
      add_history(history, event_id, "", winners.empty? ? :settlement : :pot, text)
      finish_chip_balances(state, event_id, history)
    end

    def finish_chip_balances(state, event_id, history)
      state[:players].each do |player|
        add_history(history, event_id, player, :chips,
          _("%{player} has %{chips} chips.") % {player: participant_name(player), chips: state[:chips][player]})
      end
      state[:pot] = 0
      state[:eliminated] = state[:players].select { |player| state[:chips][player].zero? }
      active = tournament_contenders(state)
      record_tournament_round(state, event_id)
      if state[:round] >= state[:options]["round_limit"] || active.size < 2
        contenders = tournament_remaining_players(state)
        highest = contenders.map { |player| state[:chips].fetch(player) }.max
        leaders = contenders.select { |player| state[:chips][player] == highest }
        record_tournament_winners(state, leaders)
        state.merge!(phase: :finished, current_player: nil, winner: leaders.one? ? leaders.first : nil, draw: !leaders.one?)
        history << result_history(event_id: event_id, winner: state[:winner], draw: state[:draw])
      else
        state[:round] += 1
        state[:order] = active.rotate((state[:round] - 1) % active.size)
        if auction_rules?(state[:options])
          state.delete(:auction)
          state.merge!(phase: :awaiting_ante, current_player: state[:players].first, totals: {}, total: 0, last_roll: [])
        else
          state.merge!(phase: :betting, current_player: state[:order].first, totals: {}, total: 0, last_roll: [])
        end
      end
    end

    def finish_auction_round(state, event_id, history)
      auction_pots(state).each do |pot|
        valid = pot[:eligible].select { |player| state[:totals].fetch(player) <= 21 }
        best = valid.map { |player| state[:totals][player] }.max
        winners = valid.select { |player| state[:totals][player] == best }
        refunded = pot[:contributors].one? || winners.empty?
        if refunded
          pot[:contributors].each { |player| state[:chips][player] += pot[:slice] }
          text = _("Unclaimed pot of %{pot} chips returned to its contributors.") % {pot: pot[:amount]}
        else
          share, remainder = pot[:amount].divmod(winners.size)
          winners.each_with_index { |player, index| state[:chips][player] += share + (index < remainder ? 1 : 0) }
          text = dice_pot_result(winners, pot[:amount])
        end
        add_history(history, event_id, "", refunded ? :settlement : :pot, text)
      end
      finish_chip_balances(state, event_id, history)
    end
  end
end

require_relative "generated/rulebooks/blackjack_dice"
