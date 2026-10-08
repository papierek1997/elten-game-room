require "securerandom"
require_relative "card_game"
require_relative "../lib/game_bots"
require_relative "../lib/scientific_war_bot"
require_relative "../lib/hidden_submissions"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class ScientificWar < CardGame
    SUIT_ORDER = %w[H S D C].freeze
    TRICK_LIMITS = (20..100).freeze
    EVENT_BUDGET = 1_900
    NONCE_PATTERN = /\A[0-9a-f]{32}\z/
    DIGEST_PATTERN = /\A[A-Za-z0-9+\/]{43}=\z/

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      kinds = history.map(&:kind)
      return "play2" if kinds.include?(:commit)
      return same_user?(event["actor"], viewer) ? "card-shuffle" : nil if kinds.include?(:swap)
      return nil unless kinds.include?(:reveal)

      cues = ["play"]
      cues << "reverse" if kinds.include?(:revolution)
      cues << "war_open" if (kinds & [:war, :forced_war]).any?
      cues << "draw" if (kinds & [:take, :joker_win]).any?
      cues
    end

    def id
      "scientific_war"
    end

    def name
      _("Scientific War")
    end

    def short_description
      _("Choose which cards to play and use their special abilities to take all your opponents' cards.")
    end

    def rule_sections
      generated_rule_sections
    end

    def minimum_players
      2
    end

    def maximum_players
      8
    end

    def supports_bots?
      true
    end

    def playable_card_navigation(replay, viewer)
      grouped = legal_actions(replay, viewer).select { |action| action["action"] == "select" }.group_by { |action| action["card"].to_s }
      grouped.empty? ? nil : card_navigation_spec(hand_id: "hand", card_actions: grouped, automatic_card_ids: grouped.keys)
    end

    def controller_change_phase_error(replay)
      _("The current game contains private data that cannot be transferred at this stage.") if pending_seats(replay.state).any?
    end

    def participant_replacement_error(replay, player:, replacement: nil)
      return nil if replay == nil || replay.finished?

      seat = player_key(replay.state, player)
      controller_change_phase_error(replay) if seat == nil || pending_reveal?(replay.state, seat)
    end

    def save_game_error(replay)
      error = super
      return error if error

      state = replay.state
      if state[:commits].keys.any? { |player| !GameRoomParticipants.bot?(player) && !state[:reveals].key?(player) }
        return _("Save the game at the beginning of a trick, before any person has chosen a card.")
      end

      nil
    end

    def restart_guard_seconds
      3
    end

    def saved_game_requires_private_data?
      true
    end

    def saved_private_data(replay, context:)
      state = replay.state
      cards = pending_seats(state).to_h do |player|
        envelope = context.hidden_submissions.reveal(session_id: context.session_id, round_id: round_id(state), user: player,
          commitment: state[:commits][player])
        raise IOError, "A chosen card could not be read" if envelope == nil

        [state[:players].index(player).to_s, { "card" => envelope.payload.to_h["card"], "nonce" => envelope.nonce }]
      end
      data = { "version" => 1, "trick" => state[:trick], "cards" => cards }
      validate_saved_private_data(replay, data)
      data
    end

    def validate_saved_private_data(replay, data)
      state = replay.state
      seats = pending_seats(state).map { |player| state[:players].index(player).to_s }
      valid = data.is_a?(Hash) && data.keys.sort == %w[cards trick version] && data["version"] == 1 &&
        data["trick"] == state[:trick] && data["cards"].is_a?(Hash) && data["cards"].keys.sort == seats.sort &&
        data["cards"].all? do |seat, item|
          player = state[:players][seat.to_i]
          item.is_a?(Hash) && item.keys.sort == %w[card nonce] && item["nonce"].to_s.match?(NONCE_PATTERN) &&
            GameRoomParticipants.bot?(player) && state[:hands][player].include?(item["card"]) &&
            HiddenSubmissions::Commitment.valid?(payload: { "card" => item["card"] }, nonce: item["nonce"], commitment: state[:commits][player])
        end
      raise ArgumentError, "Invalid private Scientific War archive" unless valid

      true
    end

    def restore_private_data(replay, data, context:)
      validate_saved_private_data(replay, data)
      state = replay.state
      data["cards"].each do |seat, item|
        context.hidden_submissions.prepare(session_id: context.session_id, round_id: round_id(state),
          user: state[:players][seat.to_i], payload: { "card" => item["card"] }, nonce: item["nonce"])
      end
      raise IOError, "Restored Scientific War cards could not be verified" unless saved_private_data(replay, context: context) == data

      true
    end

    def bot_strategy
      @bot_strategy ||= ScientificWarBot::Strategy.new
    end

    def option_definitions
      [
        OptionDefinition.new(key: "trick_limit", label: _("Trick limit (20 to 100)"), kind: :integer, default: 50,
          summary_label: _("Trick limit"))
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _("The trick limit must be from 20 to 100.") unless TRICK_LIMITS.include?(values["trick_limit"].to_i)

      nil
    end

    def options_summary(options)
      values = normalize_options(options)
      _("up to %{count} tricks") % { count: values["trick_limit"] }
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session["options"]))
      accepted = []
      seen = {}
      history = [starting_history(players)]
      events.each do |event|
        break if state[:phase] == :finished
        event_id = repository.event_id(event)
        next if seen[event_id]
        actor = repository.actor_of(event, session)
        applied = case event["action"].to_s
        when "commit" then apply_commit(state, event, actor, event_id, history)
        when "reveal" then apply_reveal(state, event, actor, event_id, history)
        when "spy_play" then apply_spy_play(state, event, actor, event_id, history)
        when "swap" then apply_swap(state, event, actor, event_id, history)
        else false
        end
        next unless applied
        accepted << event
        seen[event_id] = true
        check_event_budget(state, accepted.length, event_id, history)
      end
      Replay.new(board: nil, players: players, current_player: current_actor(state), winner: state[:winner],
        draw: state[:draw], accepted_events: accepted, history: history, state: state)
    end

    def prepare_view(replay, viewer, context: nil)
      state = replay.state
      player = player_key(state, viewer)
      return if player == nil || !state[:commits].key?(player) || context&.hidden_submissions == nil
      key = [viewer.to_s.downcase, state[:commits][player]]
      @chosen ||= {}
      return if @chosen.key?(key)

      envelope = context.hidden_submissions.reveal(session_id: context.session_id, round_id: round_id(state),
        user: viewer, commitment: state[:commits][player])
      card = envelope&.payload.to_h["card"]
      @chosen[key] = card if card != nil
    rescue HiddenSubmissions::StorageError
      nil
    end

    def automatic_action(replay, actor, context: nil)
      state = replay.state
      return nil if replay.finished? || state[:phase] != :revealing || GameRoomParticipants.bot?(actor)
      player = player_key(state, actor)
      return nil if player == nil || !pending_reveal?(state, player)
      return nil if reveal_plan(state, player, actor, context).first != :ok

      { "kind" => "command", "action" => "reveal" }
    end

    def automatic_action_allowed?(replay, actor, table_owner:)
      return true if same_user?(actor, table_owner)

      player = player_key(replay.state, actor)
      replay.state[:phase] == :revealing && player != nil && pending_reveal?(replay.state, player)
    end

    def automatic_action_due?(replay, actor, context: nil)
      automatic_action(replay, actor, context: context) != nil
    end

    def active_actors(replay)
      state = replay.state
      case state[:phase]
      when :choosing then choosers(state).reject { |player| state[:commits].key?(player) }
      when :revealing then state[:commits].keys.reject { |player| state[:reveals].key?(player) }
      when :spying then [spy(state)].compact
      else []
      end
    end

    def required_decision_key(replay, viewer)
      return nil if replay == nil || replay.finished?

      state = replay.state
      player = player_key(state, viewer)
      return nil if player == nil || state[:eliminated][player]

      choosing = state[:phase] == :choosing && choosers(state).include?(player) && !state[:commits].key?(player)
      spying = state[:phase] == :spying && spy(state) == player
      [state[:phase], state[:trick], player.downcase] if choosing || spying
    end

    def concurrent_session_input?(before, after, selection)
      first, second = before.state, after.state
      first[:trick] == second[:trick] && first[:phase] == second[:phase] &&
        [:choosing, :revealing].include?(second[:phase]) && %w[select swap reveal].include?(selection["action"].to_s)
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      player = player_key(state, actor)
      return [] if replay.finished? || player == nil || state[:eliminated][player]

      case state[:phase]
      when :choosing
        return [] if !choosers(state).include?(player) || state[:commits].key?(player)
        actions = card_actions(state, player)
        actions << { "kind" => "command", "action" => "swap" } if swap_available?(state, player)
        actions
      when :revealing
        pending_reveal?(state, player) ? [{ "kind" => "command", "action" => "reveal" }] : []
      when :spying
        same_user?(spy(state), player) ? card_actions(state, player) : []
      else
        []
      end
    end

    def bot_action_score(replay, actor, action, context: nil)
      ScientificWarBot::Evaluation.new(self, replay, actor).score(action)
    end

    def bot_observation(replay, actor)
      state = replay.state
      { "trick" => state[:trick], "phase" => state[:phase].to_s, "totals" => state[:players].to_h { |player| [player, total(state, player)] } }
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?
      player = player_key(state, actor)
      return [:not_your_turn, nil] if player == nil || state[:eliminated][player]

      if selection["kind"].to_s == "card" && selection["action"].to_s == "select"
        card = selection["card"].to_s
        return [:invalid, nil] unless state[:hands][player].include?(card)
        return spy_plan(state, player, card) if state[:phase] == :spying

        return commit_plan(state, player, actor, card, context)
      end
      case selection["action"].to_s
      when "reveal" then reveal_plan(state, player, actor, context)
      when "swap" then swap_plan(state, player)
      else [:invalid, nil]
      end
    end

    def surface_spec(replay, viewer)
      state = replay.state
      return info_surface(result_text(replay).to_s) if replay.finished?
      player = player_key(state, viewer)
      return info_surface(played_text(state)) if player == nil
      return info_surface(_("You are out of the game.")) if state[:eliminated][player]

      case state[:phase]
      when :choosing
        return info_surface(waiting_text(state, player, viewer)) if !choosers(state).include?(player) || state[:commits].key?(player)

        header = n_("Choose a card. You have %{count} card in hand.", "Choose a card. You have %{count} cards in hand.",
          state[:hands][player].length) % { count: state[:hands][player].length }
        hand = hand_surface(state, player, viewer, header)
        return hand unless swap_available?(state, player)

        command = GameSurfaces::CommandPanelSpec.new(commands: [
          GameSurfaces::Command.new(id: "swap", label: n_("Swap your hand with your pile of %{count} card",
            "Swap your hand with your pile of %{count} cards", state[:piles][player].length) % { count: state[:piles][player].length },
            enabled: true, payload: {})
        ])
        GameSurfaces::CompositeSpec.new(parts: [
          GameSurfaces::SurfacePart.new(id: "swap", surface: command),
          GameSurfaces::SurfacePart.new(id: "hand", surface: hand)
        ])
      when :revealing
        info_surface(_("Everyone has chosen. The cards are being revealed."))
      when :spying
        return info_surface(_("%{player} is looking at the chosen cards.") % { player: participant_name(spy(state)) }) unless same_user?(spy(state), player)

        hand_surface(state, player, viewer, _("You are the spy. %{cards} Choose your card.") % { cards: chosen_cards_text(state) })
      else
        info_surface(played_text(state))
      end
    end

    def turn_announcement(replay, viewer)
      return nil if replay == nil || replay.finished? || replay.state[:phase] != :spying
      return _("You are the spy. Press C to read the chosen cards, then choose yours.") if same_user?(spy(replay.state), viewer)

      _("%{player} is looking at the chosen cards.") % { player: participant_name(spy(replay.state)) }
    end

    def participant_status(replay, participant, connected: true)
      return _("out") if eliminated_from_game?(replay, participant)

      super
    end

    def eliminated_from_game?(replay, viewer)
      state = replay&.state
      return false unless state.is_a?(Hash) && state[:eliminated].is_a?(Hash)

      player = player_key(state, viewer)
      player != nil && state[:eliminated][player] == true
    end

    def shortcut_features
      [:turn, :round_summary]
    end

    def shortcut_feature_data(feature, replay, viewer)
      case feature.to_sym
      when :turn
        { label: _("read who has already chosen a card"), message: replay.finished? ? result_text(replay).to_s : played_text(replay.state) }
      when :round_summary
        entries = history_entries_for_display(replay, viewer)
        last = entries.reverse.find { |entry| entry.kind == :reveal }
        summary = entries.select do |entry|
          last != nil && entry.event_id == last.event_id && entry.field.to_s != "private" &&
            ![:start, :turn, :trick, :result].include?(entry.kind)
        end.map(&:text).join(" ")
        { label: _("read the result of the last trick"), message: last == nil ? _("No trick has been decided yet.") : summary }
      else
        super
      end
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      player = player_key(state, viewer)
      power = if player != nil && state[:phase] == :choosing && swap_available?(state, player) && !state[:commits].key?(player)
        GameShortcut.new(key: "c", label: _("use your card power"), kind: :action, action_kind: "command", action_name: "swap")
      else
        announcement_shortcut(key: "c", label: _("use your card power"), message: power_text(state, player))
      end
      [
        power,
        announcement_shortcut(key: "e", label: _("read how many cards each player owns"), message: totals_text(state)),
        announcement_shortcut(key: "r", label: _("read the current rules"), message: current_rules_text(state, player))
      ]
    end

    def history_entries_for_display(replay, viewer, surface_state: {})
      replay.history.filter_map do |entry|
        next if entry.field.to_s == "private" && !same_user?(entry.actor, viewer)
        next entry unless entry.kind == :commit && same_user?(entry.actor, viewer)

        card = (@chosen || {})[[viewer.to_s.downcase, entry.value]]
        next entry if card == nil

        displayed = entry.dup
        displayed.text = _("You chose %{card}.") % { card: playing_card_label(card) }
        displayed
      end
    end

    def describe_event(event, repository, replay, viewer)
      event_id = repository.event_id(event).to_i
      history_entries_for_display(replay, viewer).filter_map do |entry|
        next unless entry.event_id.to_i == event_id
        next if [:start, :turn, :result].include?(entry.kind)
        entry.text unless entry.text.to_s.empty?
      end
    end

    def result_text(replay)
      return super unless replay.state.is_a?(Hash) && replay.state[:limit_reached]

      [_("The trick limit was reached."), super].compact.join(" ")
    end

    private

    def initial_state(players, options)
      hands = {}
      players.each_with_index do |player, index|
        suit = SUIT_ORDER[index % SUIT_ORDER.length]
        deck = index / SUIT_ORDER.length + 1
        hands[player] = CARD_RANKS.map { |rank| "#{rank}#{suit}#{deck}" } + ["X#{index + 1}"]
      end
      { players: players, options: options, phase: :choosing, trick: 1, hands: hands,
        piles: players.to_h { |player| [player, []] }, new_hands: {}, eliminated: {}, reversed: false, carried: [],
        commits: {}, reveals: {}, powers: {}, last_trick: nil, limit_reached: false, winner: nil, draw: false }
    end

    def apply_commit(state, event, actor, id, history)
      player = player_key(state, actor)
      return false if state[:phase] != :choosing || player == nil || !choosers(state).include?(player) || state[:commits].key?(player)
      trick, digest = event["value"].to_s.split(":", 2)
      return false if trick != state[:trick].to_s
      commitment = decode_digest(digest)
      return false if commitment == nil

      state[:commits][player] = commitment
      history << HistoryEntry.new(key: "commit:#{id}:#{player.to_s.downcase}", text: _("%{player} has chosen a card.") % {
        player: participant_name(player) }, event_id: id, actor: player, kind: :commit, value: commitment)
      state[:phase] = :revealing if choosers(state).all? { |item| state[:commits].key?(item) }
      true
    end

    def apply_reveal(state, event, actor, id, history)
      player = player_key(state, actor)
      return false if state[:phase] != :revealing || player == nil || !pending_reveal?(state, player)
      trick, nonce, card = event["value"].to_s.split(":", 3)
      return false if trick != state[:trick].to_s || !nonce.to_s.match?(NONCE_PATTERN) || !state[:hands][player].include?(card)
      return false unless HiddenSubmissions::Commitment.valid?(payload: { "card" => card }, nonce: nonce, commitment: state[:commits][player])

      state[:reveals][player] = card
      return true unless choosers(state).all? { |item| state[:reveals].key?(item) }

      if spy(state) != nil
        state[:phase] = :spying
        history << entry(id, spy(state), :spying, _("Everyone else has chosen. %{player} is looking at their cards.") % {
          player: participant_name(spy(state)) })
      else
        resolve_trick(state, id, history)
      end
      true
    end

    def apply_spy_play(state, event, actor, id, history)
      player = player_key(state, actor)
      trick, card = event["value"].to_s.split(":", 2)
      return false if state[:phase] != :spying || player == nil || player != spy(state)
      return false if trick != state[:trick].to_s || !state[:hands][player].include?(card)

      state[:reveals][player] = card
      resolve_trick(state, id, history)
      true
    end

    def apply_swap(state, event, actor, id, history)
      player = player_key(state, actor)
      return false if state[:phase] != :choosing || player == nil || state[:commits].key?(player)
      return false if event["value"].to_s != state[:trick].to_s || !swap_available?(state, player)

      state[:hands][player], state[:piles][player] = state[:piles][player], state[:hands][player]
      state[:new_hands][player] = state[:new_hands][player].to_i + 1
      state[:powers].delete(player)
      text = n_("You swapped your hand with your pile. You now have %{count} card in hand.",
        "You swapped your hand with your pile. You now have %{count} cards in hand.", state[:hands][player].length) % {
          count: state[:hands][player].length }
      history << private_entry(id, player, :swap, text)
      true
    end

    def resolve_trick(state, id, history)
      plays = state[:players].each_with_object({}) { |player, result| result[player] = state[:reveals][player] if state[:reveals].key?(player) }
      plays.each { |player, card| state[:hands][player].delete_at(state[:hands][player].index(card)) }
      summary = [_("Cards: %{cards}.") % { cards: plays_text(plays) }]
      history << entry(id, "", :reveal, summary.first)
      jacks = plays.values.count { |card| playing_card_rank(card) == "J" }
      if jacks.odd?
        state[:reversed] = !state[:reversed]
        text = state[:reversed] ? _("Revolution! The order is reversed: two is now the strongest card and ace the weakest.") :
          _("Revolution! The usual order is back: ace is the strongest card again.")
        history << entry(id, "", :revolution, text)
        summary << text
      elsif jacks > 0
        text = _("The jacks cancel each other out; the card order does not change.")
        history << entry(id, "", :jacks_cancelled, text)
        summary << text
      end
      winner, kind = trick_outcome(state, plays, jacks_applied: true)
      if plays.values.count { |card| joker?(card) } > 1
        text = _("The jokers cancel each other out.")
        history << entry(id, "", :jokers_cancelled, text)
        summary << text
      end
      pot = state[:carried] + plays.values
      text = case kind
      when :take
        n_("%{player} wins the trick and takes %{count} card.", "%{player} wins the trick and takes %{count} cards.", pot.length) % {
          player: participant_name(winner), count: pot.length }
      when :joker_win
        n_("The joker cancels the war: %{player} wins the trick and takes %{count} card.",
          "The joker cancels the war: %{player} wins the trick and takes %{count} cards.", pot.length) % {
          player: participant_name(winner), count: pot.length }
      when :forced_war
        n_("The joker forces a war. %{count} card stays on the table for the next trick.",
          "The joker forces a war. %{count} cards stay on the table for the next trick.", pot.length) % { count: pot.length }
      else
        n_("War! %{count} card stays on the table for the next trick.", "War! %{count} cards stay on the table for the next trick.",
          pot.length) % { count: pot.length }
      end
      if winner != nil
        state[:piles][winner].concat(pot)
        state[:carried] = []
      else
        state[:carried] = pot
      end
      history << entry(id, winner || "", kind == :forced_war ? :forced_war : kind, text)
      summary << text
      state[:powers] = grant_powers(plays, id, history, summary)
      refill_and_eliminate(state, id, history, summary)
      state[:last_trick] = summary.join(" ")
      next_trick(state, id, history)
    end

    def trick_outcome(state, plays, jacks_applied: false)
      jacks = plays.values.count { |card| playing_card_rank(card) == "J" }
      reversed = jacks_applied || jacks.even? ? state[:reversed] : !state[:reversed]
      jokers = plays.select { |_player, card| joker?(card) }.keys
      normal = plays.reject { |_player, card| joker?(card) }
      best = normal.values.map { |card| strength(card, reversed) }.max
      tied = best == nil ? [] : normal.select { |_player, card| strength(card, reversed) == best }.keys
      if jokers.length == 1
        return [jokers.first, :joker_win] if tied.length != 1

        return [nil, :forced_war]
      end
      tied.length == 1 ? [tied.first, :take] : [nil, :war]
    end

    def grant_powers(plays, id, history, summary)
      powers = {}
      queens = plays.select { |_player, card| playing_card_rank(card) == "Q" }.keys
      if queens.length == 1
        powers[queens.first] = "Q"
        text = _("%{player} played a queen and will see the other players' cards in the next trick before choosing.") % {
          player: participant_name(queens.first) }
        history << entry(id, queens.first, :spy_power, text)
        summary << text
      elsif queens.length > 1
        text = _("The queens cancel each other out.")
        history << entry(id, "", :queens_cancelled, text)
        summary << text
      end
      plays.each do |player, card|
        case playing_card_rank(card)
        when "3"
          powers[player] = "3"
          text = _("%{player} played a three and may check the hand sizes in the next trick.") % { player: participant_name(player) }
          history << entry(id, player, :three_power, text)
          summary << text
        when "8"
          powers[player] = "8"
          text = _("%{player} played an eight and may swap their hand with their pile in the next trick.") % { player: participant_name(player) }
          history << entry(id, player, :eight_power, text)
          summary << text
        end
      end
      powers
    end

    def refill_and_eliminate(state, id, history, summary)
      state[:players].each do |player|
        next if state[:eliminated][player] || !state[:hands][player].empty?

        if state[:piles][player].any?
          count = state[:piles][player].length
          state[:hands][player], state[:piles][player] = state[:piles][player], []
          state[:new_hands][player] = state[:new_hands][player].to_i + 1
          history << private_entry(id, player, :refill, n_("Your hand is empty, so you take %{count} card from your pile into your hand.",
            "Your hand is empty, so you take %{count} cards from your pile into your hand.", count) % { count: count })
        else
          state[:eliminated][player] = true
          state[:powers].delete(player)
          text = _("%{player} has no cards left and is out of the game.") % { player: participant_name(player) }
          history << entry(id, player, :eliminated, text)
          summary << text
        end
      end
    end

    def next_trick(state, id, history)
      remaining = active_players(state)
      if remaining.length <= 1
        finish_game(state, remaining, id, history)
      elsif state[:trick] >= state[:options]["trick_limit"].to_i
        finish_by_limit(state, id, history)
      else
        state.update(trick: state[:trick] + 1, commits: {}, reveals: {}, phase: :choosing)
        history << entry(id, "", :trick, _("Trick %{number}.") % { number: state[:trick] })
      end
    end

    def check_event_budget(state, count, id, history)
      return if state[:phase] != :choosing || state[:commits].any?
      return if count + 3 * active_players(state).length <= EVENT_BUDGET

      finish_by_limit(state, id, history)
    end

    def finish_by_limit(state, id, history)
      remaining = active_players(state)
      most = remaining.map { |player| total(state, player) }.max
      state[:limit_reached] = true
      finish_game(state, remaining.select { |player| total(state, player) == most }, id, history)
    end

    def finish_game(state, leaders, id, history)
      state.update(phase: :finished, commits: {}, reveals: {}, powers: {})
      state[:winner] = leaders.first if leaders.length == 1
      state[:draw] = leaders.length != 1
      history << result_history(event_id: id, winner: state[:winner], draw: state[:draw])
    end

    def commit_plan(state, player, actor, card, context)
      return [:not_your_turn, nil] if state[:phase] != :choosing || !choosers(state).include?(player)
      return [:already_submitted, nil] if state[:commits].key?(player)
      return [:invalid, nil] if context == nil || context.hidden_submissions == nil

      context.hidden_submissions.discard(session_id: context.session_id, round_id: "trick:#{state[:trick] - 1}", user: actor) if state[:trick] > 1
      envelope = context.hidden_submissions.prepare(session_id: context.session_id, round_id: round_id(state), user: actor,
        payload: { "card" => card }, nonce: SecureRandom.hex(16))
      (@chosen ||= {})[[actor.to_s.downcase, envelope.commitment]] = envelope.payload["card"]
      [:ok, event_plan("commit", "#{state[:trick]}:#{encode_digest(envelope.commitment)}")]
    rescue HiddenSubmissions::StorageError
      [:local_storage_unavailable, nil]
    end

    def reveal_plan(state, player, actor, context)
      return [:invalid, nil] if state[:phase] != :revealing || !pending_reveal?(state, player)
      return [:invalid, nil] if context == nil || context.hidden_submissions == nil

      envelope = context.hidden_submissions.reveal(session_id: context.session_id, round_id: round_id(state), user: actor,
        commitment: state[:commits][player])
      return [:invalid, nil] if envelope == nil || envelope.commitment != state[:commits][player] || !context.hidden_submissions.verify(envelope)
      card = envelope.payload.to_h["card"].to_s
      return [:invalid, nil] if !envelope.nonce.to_s.match?(NONCE_PATTERN) || !state[:hands][player].include?(card)

      [:ok, event_plan("reveal", "#{state[:trick]}:#{envelope.nonce}:#{card}")]
    rescue HiddenSubmissions::StorageError
      [:local_storage_unavailable, nil]
    end

    def spy_plan(state, player, card)
      return [:not_your_turn, nil] if player != spy(state)

      [:ok, event_plan("spy_play", "#{state[:trick]}:#{card}")]
    end

    def swap_plan(state, player)
      return [:invalid, nil] if state[:phase] != :choosing || state[:commits].key?(player) || !swap_available?(state, player)

      [:ok, event_plan("swap", state[:trick].to_s)]
    end

    def encode_digest(hex)
      [[hex].pack("H*")].pack("m0")
    end

    def decode_digest(body)
      return nil unless body.to_s.match?(DIGEST_PATTERN)
      decoded = body.unpack1("m0")
      return nil if decoded.bytesize != 32 || [decoded].pack("m0") != body

      decoded.unpack1("H*")
    rescue ArgumentError
      nil
    end

    def round_id(state)
      "trick:#{state[:trick]}"
    end

    def pending_seats(state)
      state[:commits].keys.reject { |player| state[:reveals].key?(player) }
    end

    def pending_reveal?(state, player)
      state[:commits].key?(player) && !state[:reveals].key?(player)
    end

    def spy(state)
      player = state[:powers].key("Q")
      player != nil && active_players(state).include?(player) ? player : nil
    end

    def choosers(state)
      active_players(state) - [spy(state)].compact
    end

    def swap_available?(state, player)
      state[:powers][player] == "8" && state[:piles][player].any?
    end

    def active_players(state)
      state[:players].reject { |player| state[:eliminated][player] }
    end

    def current_actor(state)
      state[:phase] == :spying ? spy(state) : nil
    end

    def total(state, player)
      state[:hands][player].length + state[:piles][player].length
    end

    def joker?(card)
      playing_card_rank(card) == "X"
    end

    def strength(card, reversed)
      index = CARD_RANKS.index(playing_card_rank(card)).to_i
      reversed ? CARD_RANKS.length - 1 - index : index
    end

    def card_actions(state, player)
      state[:hands][player].uniq.map { |card| { "kind" => "card", "action" => "select", "zone" => "hand", "card" => card } }
    end

    def hand_surface(state, player, viewer, header)
      hand = state[:hands][player]
      cards = hand.sort_by { |card| [joker?(card) ? 1 : 0, CARD_RANKS.index(playing_card_rank(card)).to_i, card] }.map do |card|
        GameSurfaces::Card.new(id: card, label: playing_card_label(card), value: card)
      end
      GameSurfaces::CardTableSpec.new(zones: [
        GameSurfaces::CardZoneSpec.new(id: "hand", header: header, cards: cards, empty_label: _("Your hand is empty"),
          hand_order: hand.dup, hand_epoch: "#{viewer.to_s.downcase}:scientific_war:#{state[:new_hands][player].to_i}")
      ])
    end

    def info_surface(label)
      GameSurfaces::CardTableSpec.new(zones: [
        GameSurfaces::CardZoneSpec.new(id: "actions", header: label, cards: [], empty_label: label)
      ])
    end

    def waiting_text(state, player, viewer)
      chosen = (@chosen || {})[[viewer.to_s.downcase, state[:commits][player]]]
      first = if same_user?(spy(state), player)
        _("You are the spy and will choose after the others.")
      elsif chosen != nil
        _("You chose %{card}.") % { card: playing_card_label(chosen) }
      else
        _("You have chosen your card.")
      end
      [first, played_text(state)].join(" ")
    end

    def played_text(state)
      case state[:phase]
      when :choosing
        done = choosers(state).select { |player| state[:commits].key?(player) }
        waiting = choosers(state).reject { |player| state[:commits].key?(player) }
        parts = [_("Trick %{number}.") % { number: state[:trick] }]
        parts << (done.empty? ? _("Nobody has chosen a card yet.") : _("Already chosen: %{players}.") % { players: names(done) })
        parts << _("Still choosing: %{players}.") % { players: names(waiting) } if waiting.any?
        parts << _("%{player} is the spy and chooses last.") % { player: participant_name(spy(state)) } if spy(state)
        parts.join(" ")
      when :revealing
        _("Everyone has chosen. The cards are being revealed.")
      when :spying
        _("%{player} is looking at the chosen cards.") % { player: participant_name(spy(state)) }
      else
        _("The game is finished.")
      end
    end

    def chosen_cards_text(state)
      plays = state[:reveals].reject { |player, _card| player == spy(state) }
      _("Chosen cards: %{cards}.") % { cards: plays_text(plays) }
    end

    def power_text(state, player)
      return _("You have no card power in this trick.") if player == nil || state[:phase] == :finished

      case state[:powers][player]
      when "Q"
        return chosen_cards_text(state) if state[:phase] == :spying && spy(state) == player

        _("You are the spy. You will see the chosen cards when everyone else has chosen.")
      when "3"
        others = active_players(state) - [player]
        counts = others.map do |other|
          n_("%{player}: %{count} card", "%{player}: %{count} cards", state[:hands][other].length) % {
            player: participant_name(other), count: state[:hands][other].length }
        end
        _("Cards in hand: %{counts}.") % { counts: counts.join("; ") }
      when "8"
        return _("Your pile is empty, so there is nothing to swap.") if state[:piles][player].empty?

        _("You can swap your hand with your pile before choosing a card.")
      else
        _("You have no card power in this trick.")
      end
    end

    def current_rules_text(state, player)
      parts = [state[:reversed] ? _("Card order: reversed; two is the strongest card and ace the weakest.") :
        _("Card order: normal; ace is the strongest card and two the weakest.")]
      if state[:carried].any?
        parts << n_("%{count} card from a war is waiting on the table.", "%{count} cards from wars are waiting on the table.",
          state[:carried].length) % { count: state[:carried].length }
      end
      parts << _("%{player} is the spy in this trick.") % { player: participant_name(spy(state)) } if spy(state) && spy(state) != player
      if player != nil && state[:phase] != :finished
        parts << case state[:powers][player]
        when "Q" then _("Your power: you are the spy in this trick.")
        when "3" then _("Your power: you may check the hand sizes with C.")
        when "8" then _("Your power: you may swap your hand with your pile with C.")
        else _("You have no card power in this trick.")
        end
      end
      parts.join(" ")
    end

    def totals_text(state)
      state[:players].map do |player|
        next _("%{player}: out") % { player: participant_name(player) } if state[:eliminated][player]

        n_("%{player}: %{count} card", "%{player}: %{count} cards", total(state, player)) % {
          player: participant_name(player), count: total(state, player) }
      end.join("; ") + "."
    end

    def plays_text(plays)
      plays.map { |player, card| _("%{player}: %{card}") % { player: participant_name(player), card: playing_card_label(card) } }.join("; ")
    end

    def names(players)
      players.map { |player| participant_name(player) }.join(", ")
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def entry(id, actor, kind, text)
      HistoryEntry.new(key: "#{kind}:#{id}:#{actor.to_s.downcase}", text: text, event_id: id, actor: actor, kind: kind)
    end

    def private_entry(id, actor, kind, text)
      HistoryEntry.new(key: "#{kind}:#{id}:#{actor.to_s.downcase}", text: text, event_id: id, actor: actor, kind: kind, field: "private")
    end
  end
end

require_relative 'generated/rulebooks/scientific_war'
