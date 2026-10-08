require_relative "card_game"
require_relative "../lib/game_bots"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class War < CardGame
    include PublicHistoryAnnouncements

    SHORT_RANKS = %w[9 T J Q K A].freeze
    BATTLE_LIMITS = (20..300).freeze

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      return "shuffle" if event["action"].to_s == "deal"
      kinds = history.map(&:kind)
      cues = ["play"]
      cues << "war_open" if kinds.include?(:war)
      cues << "draw" if kinds.include?(:take)
      cues
    end

    def id
      "war"
    end

    def name
      _("War")
    end

    def short_description
      _("Turn over cards and take your opponents' cards whenever yours is the highest.")
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

    def bot_strategy
      @bot_strategy ||= GameRoomBots::RandomStrategy.new
    end

    def decks
      [
        OptionChoice.new(value: "short", label: _("24 cards, from nine to ace")),
        OptionChoice.new(value: "full", label: _("52 cards, from two to ace"))
      ]
    end

    def option_definitions
      [
        OptionDefinition.new(key: "deck", label: _("Deck"), kind: :choice, default: "short", choices: decks),
        OptionDefinition.new(key: "battle_limit", label: _("Battle limit (20 to 300)"), kind: :integer, default: 20,
          summary_label: _("Battle limit"))
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _("The battle limit must be from 20 to 300.") unless BATTLE_LIMITS.include?(values["battle_limit"].to_i)

      nil
    end

    def options_summary(options)
      values = normalize_options(options)
      deck = decks.find { |choice| choice.value == values["deck"] }&.label || values["deck"]
      _("%{deck}; up to %{count} battles") % { deck: deck, count: values["battle_limit"] }
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
        when "deal" then apply_deal(state, event, actor, repository, history)
        when "play" then apply_play(state, event, actor, repository, history)
        else false
        end
        next unless applied
        accepted << event
        seen[event_id] = true
      end
      Replay.new(board: nil, players: players, current_player: current_actor(state), winner: state[:winner],
        draw: state[:draw], accepted_events: accepted, history: history, state: state)
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || replay.state[:phase] != :awaiting_deal
      return nil unless same_user?(actor, replay.players.first)

      { "kind" => "command", "action" => "deal" }
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || !same_user?(replay.current_player, actor)

      [{ "kind" => "command", "action" => "play" }]
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?
      action = selection["action"].to_s
      action = selection["card"].to_s if selection["kind"].to_s == "card" && action == "select" && selection["zone"].to_s == "actions"
      case action
      when "deal"
        return [:not_your_turn, nil] unless same_user?(actor, replay.players.first)
        return [:invalid, nil] if state[:phase] != :awaiting_deal || context&.random_source == nil

        [:ok, event_plan("deal", card_seed(context.random_source))]
      when "play"
        return [:not_your_turn, nil] unless same_user?(replay.current_player, actor)

        [:ok, event_plan("play", step_key(state))]
      else
        [:invalid, nil]
      end
    end

    def surface_spec(replay, viewer)
      state = replay.state
      return action_surface([], _("Waiting for the cards to be dealt")) if state[:phase] == :awaiting_deal

      if replay.finished? || !same_user?(replay.current_player, viewer)
        label = replay.finished? ? result_text(replay) : current_turn_shortcut_text(replay, viewer)
        return action_surface([], label)
      end

      label = state[:depth] > 0 ? _("War. Play your cards") : _("Play your top card")
      action_surface([GameSurfaces::Card.new(id: "play", label: label, value: "play")],
        n_("Your pile: %{count} card. Press Enter to play", "Your pile: %{count} cards. Press Enter to play",
          pile(state, viewer).length) % { count: pile(state, viewer).length })
    end

    def participant_status(replay, participant, connected: true)
      return _("out") if eliminated_from_game?(replay, participant)

      super
    end

    def eliminated_from_game?(replay, viewer)
      state = replay&.state
      return false unless state.is_a?(Hash) && state[:phase] != :awaiting_deal

      player = player_key(state, viewer)
      player != nil && state[:eliminated][player] == true
    end

    def shortcut_features
      super + [:table_cards, :round_summary]
    end

    def shortcut_feature_data(feature, replay, viewer)
      case feature.to_sym
      when :table_cards
        { message: table_text(replay.state, viewer) }
      when :round_summary
        last = history_entries_for_display(replay, viewer).reverse.find { |entry| [:take, :carried].include?(entry.kind) }
        { label: _("read the result of the last battle"), message: last == nil ? _("No battle has been decided yet.") : last.text }
      else
        super
      end
    end

    def custom_game_shortcuts(replay, viewer)
      [
        GameShortcut.new(key: "space", label: _("play your top card"), kind: :action, action_kind: "command", action_name: "play"),
        announcement_shortcut(key: "e", label: _("read card counts"), message: counts_text(replay.state)),
        GameShortcut.new(key: "t", modifiers: [:control], label: _("read the battle number"), kind: :announcement,
          message: battle_number_text(replay.state))
      ]
    end

    def restart_guard_seconds
      3
    end

    def history_entries_for_display(replay, viewer, surface_state: {})
      replay.history.map do |entry|
        next entry unless entry.field.to_s == "war"

        displayed = entry.dup
        displayed.text = displayed_text(entry, viewer)
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

    def bot_observation(replay, actor)
      state = replay.state
      { "current_player" => replay.current_player, "counts" => state[:piles].transform_values(&:length), "battle" => state[:battle] }
    end

    def result_text(replay)
      return super unless replay.state.is_a?(Hash) && replay.state[:limit_reached]

      [_("The battle limit was reached."), super].compact.join(" ")
    end

    private

    def initial_state(players, options)
      { players: players, options: options, phase: :awaiting_deal, seed: nil,
        piles: players.to_h { |player| [player, []] }, eliminated: {}, battle: 0, depth: 0,
        contenders: [], played: [], faces: {}, table: [], carried: [], last_battle: nil,
        limit_reached: false, winner: nil, draw: false }
    end

    def apply_deal(state, event, actor, repository, history)
      return false if state[:phase] != :awaiting_deal || !same_user?(actor, state[:players].first)
      seed = event["value"].to_s
      return false unless seed.match?(/\A[0-9a-f]{32}\z/)

      shuffled_cards(war_deck(state[:options]), seed).each_with_index do |card, index|
        state[:piles][state[:players][index % state[:players].length]] << card
      end
      state.update(phase: :playing, seed: seed)
      start_battle(state)
      id = repository.event_id(event)
      counts = state[:players].map { |player| state[:piles][player].length }.uniq
      text = if counts.length == 1
        n_("Cards were dealt: %{count} card each.", "Cards were dealt: %{count} cards each.", counts.first) % { count: counts.first }
      else
        _("Cards were dealt. %{counts}") % { counts: counts_text(state) }
      end
      history << entry(id, actor, :deal, text)
      true
    end

    def apply_play(state, event, actor, repository, history)
      return false if state[:phase] != :playing || event["value"].to_s != step_key(state)
      player = current_actor(state)
      return false if player == nil || !same_user?(player, actor)

      cards = state[:piles][player]
      hidden = state[:depth] > 0 && cards.length >= 2 ? cards.shift : nil
      card = cards.shift
      state[:table] << { player: player, card: hidden, hidden: true } if hidden
      state[:table] << { player: player, card: card, hidden: false }
      state[:faces][player] = card
      state[:played] << player
      id = repository.event_id(event)
      text = if hidden
        _("%{player} places a hidden card and plays %{card}.") % { player: participant_name(player), card: playing_card_label(card) }
      else
        _("%{player} plays %{card}.") % { player: participant_name(player), card: playing_card_label(card) }
      end
      history << entry(id, player, :play, text)
      resolve_step(state, id, history) if state[:played].length == state[:contenders].length
      true
    end

    def resolve_step(state, id, history)
      best = state[:faces].values.map { |card| rank_value(card) }.max
      tied = state[:contenders].select { |player| rank_value(state[:faces][player]) == best }
      if tied.length == 1
        collect(state, tied.first, id, history, false)
        return
      end

      history << entry(id, "", :war, _("War between %{players}!") % { players: tied.map { |player| participant_name(player) }.join(", ") })
      able = tied.reject { |player| state[:piles][player].empty? }
      if able.length == 1
        collect(state, able.first, id, history, true)
      elsif able.empty?
        state[:carried] += state[:table].map { |item| item[:card] }
        text = n_("Nobody can continue the war. %{count} card stays on the table for the next battle.",
          "Nobody can continue the war. %{count} cards stay on the table for the next battle.",
          state[:carried].length) % { count: state[:carried].length }
        history << entry(id, "", :carried, text)
        state[:last_battle] = history.last
        finish_battle(state, id, history)
      else
        state.update(depth: state[:depth] + 1, contenders: able, played: [], faces: {})
      end
    end

    def collect(state, winner, id, history, by_default)
      war = state[:depth] > 0 || by_default
      spoils = { "winner" => winner, "default" => by_default,
        "hidden" => state[:table].select { |item| item[:hidden] }.map { |item| [item[:player], item[:card]] },
        "open" => state[:carried] + state[:table].reject { |item| item[:hidden] }.map { |item| item[:card] } }
      pot = state[:carried] + state[:table].map { |item| item[:card] }
      state[:piles][winner].concat(shuffled_cards(pot, "#{state[:seed]}:#{state[:battle]}"))
      state[:carried] = []
      template = if by_default
        n_("%{player} wins the war because the others have no cards left, and takes %{count} card.",
          "%{player} wins the war because the others have no cards left, and takes %{count} cards.", pot.length)
      else
        n_("%{player} wins the battle and takes %{count} card.", "%{player} wins the battle and takes %{count} cards.", pot.length)
      end
      text = template % { player: participant_name(winner), count: pot.length }
      taken = entry(id, winner, :take, text)
      if war
        taken.field = "war"
        taken.value = spoils.merge("count" => pot.length)
      end
      history << taken
      state[:last_battle] = taken
      finish_battle(state, id, history)
    end

    def finish_battle(state, id, history)
      state[:players].each do |player|
        next if state[:eliminated][player] || !state[:piles][player].empty?

        state[:eliminated][player] = true
        history << entry(id, player, :eliminated, _("%{player} has no cards left and is out of the game.") % { player: participant_name(player) })
      end
      state[:battle] += 1
      remaining = active_players(state)
      if remaining.length <= 1
        finish_game(state, remaining, id, history)
      elsif state[:battle] >= state[:options]["battle_limit"].to_i
        most = remaining.map { |player| state[:piles][player].length }.max
        state[:limit_reached] = true
        finish_game(state, remaining.select { |player| state[:piles][player].length == most }, id, history)
      else
        start_battle(state)
      end
    end

    def finish_game(state, leaders, id, history)
      state.update(phase: :finished, contenders: [], played: [], faces: {})
      state[:winner] = leaders.first if leaders.length == 1
      state[:draw] = leaders.length != 1
      history << result_history(event_id: id, winner: state[:winner], draw: state[:draw])
    end

    def start_battle(state)
      state.update(depth: 0, contenders: active_players(state), played: [], faces: {}, table: [])
    end

    def active_players(state)
      state[:players].reject { |player| state[:eliminated][player] || state[:piles][player].empty? }
    end

    def current_actor(state)
      return nil if state[:phase] != :playing

      state[:contenders].find { |player| !state[:played].include?(player) }
    end

    def step_key(state)
      "#{state[:battle]}.#{state[:depth]}"
    end

    def war_deck(options)
      ranks = options["deck"].to_s == "full" ? CARD_RANKS : SHORT_RANKS
      CARD_SUITS.flat_map { |suit| ranks.map { |rank| "#{rank}#{suit}" } }
    end

    def rank_value(card)
      CARD_RANKS.index(playing_card_rank(card)).to_i
    end

    def pile(state, viewer)
      player = player_key(state, viewer)
      player == nil ? [] : state[:piles][player]
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def table_text(state, viewer = nil)
      me = player_key(state, viewer)
      order = ([me] + state[:players]).compact.uniq
      parts = order.filter_map do |player|
        items = state[:table].select { |item| item[:player] == player }
        next if items.empty?

        pieces = items.reject { |item| item[:hidden] }.map { |item| playing_card_label(item[:card]) }
        hidden = items.count { |item| item[:hidden] }
        pieces << n_("%{count} hidden card", "%{count} hidden cards", hidden) % { count: hidden } if hidden > 0
        _("%{player}: %{card}") % { player: participant_name(player), card: pieces.join(", ") }
      end
      if state[:carried].any?
        parts << n_("%{count} card left from the previous war", "%{count} cards left from the previous war",
          state[:carried].length) % { count: state[:carried].length }
      end
      parts.empty? ? _("No cards are on the table.") : parts.join(". ") + "."
    end

    def battle_number_text(state)
      limit = state[:options]["battle_limit"].to_i
      return _("Battles played: %{count} of %{limit}.") % { count: state[:battle], limit: limit } if state[:phase] == :finished

      _("Battle %{number} of %{limit}.") % { number: state[:battle] + 1, limit: limit }
    end

    def displayed_text(entry, viewer)
      data = entry.value
      return entry.text.to_s unless entry.field.to_s == "war" && data.is_a?(Hash)

      winner = data["winner"]
      count = data["count"].to_i
      hidden = data["hidden"].to_a
      mine = hidden.select { |player, _card| same_user?(player, viewer) }.map(&:last)
      others = hidden.reject { |player, _card| same_user?(player, viewer) }
      parts = []
      if same_user?(winner, viewer)
        parts << if data["default"]
          n_("You win the war because the others have no cards left, and take %{count} card.",
            "You win the war because the others have no cards left, and take %{count} cards.", count) % { count: count }
        else
          n_("You win the war and take %{count} card.", "You win the war and take %{count} cards.", count) % { count: count }
        end
        owners = others.map(&:first).uniq
        if owners.length == 1
          parts << _("Your opponent's hidden cards: %{cards}.") % { cards: card_list(others.map(&:last)) }
        elsif owners.length > 1
          parts << _("Opponents' hidden cards: %{cards}.") % { cards: grouped_cards(others) }
        end
        parts << _("Your hidden cards: %{cards}.") % { cards: card_list(mine) } if mine.any?
      else
        parts << (data["default"] ? entry.text.to_s : n_("%{player} wins the war and takes %{count} card.",
          "%{player} wins the war and takes %{count} cards.", count) % { player: participant_name(winner), count: count })
        parts << _("Your hidden cards: %{cards}.") % { cards: card_list(mine) } if mine.any?
        others.map(&:first).uniq.each do |player|
          cards = others.select { |owner, _card| owner == player }.map(&:last)
          parts << _("Hidden cards of %{player}: %{cards}.") % { player: participant_name(player), cards: card_list(cards) }
        end
      end
      parts << _("Other cards: %{cards}.") % { cards: card_list(data["open"].to_a) } if data["open"].to_a.any?
      parts.join(" ")
    end

    def card_list(cards)
      cards.map { |card| playing_card_label(card) }.join(", ")
    end

    def grouped_cards(pairs)
      pairs.map(&:first).uniq.map do |player|
        _("%{player}: %{card}") % { player: participant_name(player), card: card_list(pairs.select { |owner, _card| owner == player }.map(&:last)) }
      end.join("; ")
    end

    def counts_text(state)
      state[:players].map do |player|
        n_("%{player}: %{count} card", "%{player}: %{count} cards", state[:piles][player].length) % {
          player: participant_name(player), count: state[:piles][player].length }
      end.join("; ") + "."
    end

    def entry(id, actor, kind, text)
      HistoryEntry.new(key: "#{kind}:#{id}:#{actor.to_s.downcase}", text: text, event_id: id, actor: actor, kind: kind)
    end

    def action_surface(cards, label)
      GameSurfaces::CardTableSpec.new(zones: [
        GameSurfaces::CardZoneSpec.new(id: "actions", header: cards.empty? ? "" : label, cards: cards, empty_label: label)
      ])
    end
  end
end

require_relative 'generated/rulebooks/war'
