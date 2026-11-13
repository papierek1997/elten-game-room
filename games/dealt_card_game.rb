require_relative 'card_game'
require_relative '../lib/game_bots'
require_relative '../lib/game_card_wire'
require_relative '../lib/private_card_game'

module GameRoomGames
  module DealtCardPrivate
    include GameRoomPrivateCardGame
    private
    def private_event_card(event, _state); event['value'] if event['action'] == 'play'; end
  end

  # Round lifecycle and hand controls for games whose only decision is one
  # card. Rules, captures and scoring remain in the individual game models.
  class DealtCardGame < CardGame
    using GameRoomLocalization::Translations
    include PublicHistoryAnnouncements
    prepend DealtCardPrivate

    def supports_bots?; true; end
    def player_spatial_audio?; true; end
    def rule_sections; generated_rule_sections; end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session['options']))
      GameRoomPrivateCardLedger.initialize_state(state, session) if GameRoomPrivateCards.enabled?(session)
      history = [starting_history(players)]
      accepted = []
      events.each do |event|
        break if state[:winner] || state[:draw]
        accepted << event if apply_replay_event(state, event, session, repository, history)
      end
      Replay.new(players: players, board: nil, state: state, accepted_events: accepted, history: history,
        current_player: state[:current_player], winner: state[:winner], draw: state[:draw])
    end

    def incremental_replay(replay, session, events, repository)
      state = replay.state
      events.each do |event|
        break if replay.finished?
        if apply_replay_event(state, event, session, repository, replay.history)
          decisions = GameRoomParticipantDecisionEvents.for(replay)
          unless decisions.equal?(replay.accepted_events)
            actor = repository.actor_of(event, session)
            decisions << event.merge('__replay_actor' => actor, 'actor' => actor)
          end
          replay.accepted_events << event
        end
        replay.current_player, replay.winner, replay.draw = state.values_at(:current_player, :winner, :draw)
      end
      replay
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || !same_user?(actor, replay.players.first)
      return nil unless [:awaiting_deal, :round_complete].include?(replay.state[:phase]) && valid_roster?(replay.state)
      {'kind' => 'command', 'action' => 'deal'}
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || replay.state[:phase] != :playing || !same_user?(replay.current_player, actor)
      legal_cards(replay.state, actor).map do |card|
        {'kind' => 'card', 'action' => 'select', 'zone' => 'hand', 'card' => card, 'card_id' => card}
      end
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      state = replay.state
      if selection['kind'] == 'command' && selection['action'] == 'deal'
        return [:not_your_turn, nil] unless same_user?(actor, replay.players.first)
        return [:invalid, nil] unless [:awaiting_deal, :round_complete].include?(state[:phase])
        return [:invalid, nil] unless valid_roster?(state)
        template, seats = deal_recipe(state)
        return [:ok, server_seed_plan('deal', template: template, seats: seats)] if context&.server_random
        return [:invalid, nil] unless context&.random_source
        seed = card_seed(context.random_source)
        dealer = state[:dealer] ? (state[:dealer] + 1) % state[:seats].size : seed.to_i(16) % state[:seats].size
        return [:ok, event_plan('deal', "#{state[:round] + 1}|#{dealer}|#{seed}")]
      end
      return [:not_your_turn, nil] unless same_user?(replay.current_player, actor)
      return [:invalid, nil] unless selection['kind'] == 'card' && selection['action'] == 'select' && selection['zone'] == 'hand'
      card = selection['card'].to_s
      return [:card_not_in_hand, nil] unless hand_for(state, actor).include?(card)
      return [:must_follow_suit, nil] unless legal_cards(state, actor).include?(card)
      [:ok, event_plan('play', card)]
    end

    def move_error(status)
      return _("This card is not in your hand.") if status == :card_not_in_hand
      return _("You must follow the suit that was led.") if status == :must_follow_suit
      super
    end

    def hand_sorting_available?(replay, viewer)
      !hand_for(replay.state, viewer).empty?
    end

    def playable_card_navigation(replay, viewer)
      actions = legal_actions(replay, viewer).select { |action| action['kind'] == 'card' }
      actions = actions.group_by { |action| action['card_id'] }
      return nil if actions.empty?
      card_navigation_spec(hand_id: 'hand', card_actions: actions, automatic_card_ids: actions.keys)
    end

    def surface_spec(replay, viewer)
      state = replay.state
      return GameSurfaces::QuestionSpec.new(id: 'table', prompt: name, mode: :information,
        value: table_information_text(state)) unless state[:players].any? { |player| same_user?(player, viewer) }
      hand = hand_for(state, viewer)
      cards = hand_cards_for_display(hand).map do |card|
        GameSurfaces::Card.new(id: card, value: card, label: playing_card_label(card),
          sort_keys: standard_hand_sort_keys(rank: playing_card_rank(card), suit: playing_card_suit(card), position: hand.index(card)))
      end
      GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(id: 'hand', header: _("Your hand"),
        cards: cards, hand_order: hand.dup, hand_epoch: [viewer, state[:round], state[:deal_group]].join(':'),
        empty_label: _("Your hand is empty"))])
    end

    def required_decision_key(replay, viewer)
      key = super
      key && key + [replay.state[:round], replay.state[:play_count]]
    end

    def shortcut_features
      super + [:hand, :table_cards, :table_cards_list, :round_summary, :scores]
    end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      case feature
      when :hand
        hand = hand_cards_for_display(hand_for(state, viewer))
        {message: hand.empty? ? _("Your hand is empty") : _("Your hand: %{cards}.") % {cards: cards_text(hand)}}
      when :table_cards then {message: table_information_text(state)}
      when :table_cards_list
        cards = table_cards(state)
        {kind: :browse, prompt: _("Cards on the table"), choices: cards.empty? ?
          [ShortcutChoice.new(value: nil, label: _("No cards on the table"))] :
          cards.map { |card| ShortcutChoice.new(value: card, label: playing_card_label(card)) }}
      when :round_summary then {message: round_information_text(state)}
      when :scores then {message: scores_text(state)}
      else super
      end
    end

    def participant_scores(replay)
      replay.players.to_h { |player| [player, replay.state[:scores].fetch(unit_for(replay.state, player))] }
    end

    def tournament_scores(replay, options:); replay.state[:scores].dup; end
    def tournament_placement_scores(replay, options:)
      {scores: tournament_scores(replay, options: options), order: score_order}
    end

    def tournament_placement_result(replay, options:)
      super.merge(winners: winning_units(replay.state), draw: false)
    end

    def tournament_forfeit_continuation(_replay, losing_unit:, options:)
      {'status' => 'cannot_continue'}
    end

    def tournament_scored_checkpoint(replay, options:)
      return {'status' => 'unsupported'} if replay.state[:private_error]
      replay.state[:tournament_checkpoint] || {'status' => 'none'}
    end

    def bot_allied?(replay, first, second)
      unit_for(replay.state, first) == unit_for(replay.state, second)
    end

    def bot_reward(replay, actor)
      return 0.0 if !replay.finished? || replay.draw
      same_user?(replay.winner, unit_for(replay.state, actor)) ? 1.0 : -1.0
    end

    def result_text(replay)
      return nil unless replay.finished?
      winners = winning_units(replay.state).map { |unit| unit_label(replay.state, unit) }
      return _("%{player} won the game.") % {player: winners.first} if winners.size == 1
      _("The game ended in a draw.")
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      return 'shuffle' if event['action'] == 'deal'
      cues = []
      cues << 'play' if history.any? { |entry| entry.kind == :play }
      cues << 'shuffle' if history.any? { |entry| entry.kind == :redeal }
      cues
    end

    protected

    # Presentation and H share this order; never reorder the authoritative hand.
    def hand_cards_for_display(hand)
      hand
    end

    def score_order; 'higher'; end

    def initial_state(players, options)
      assignment = team_assignment(options, players: players)
      units = assignment ? assignment.team_ids : players.dup
      seats = if assignment
        assignment.team_size.times.flat_map { |index| units.map { |unit| assignment.members_for(unit)[index] } }
      else players.dup
      end
      {players: players, seats: seats, options: options, units: units,
        unit_for: players.to_h { |player| [player, assignment ? "team:#{assignment.team_index_for(player)}" : player] },
        scores: units.to_h { |unit| [unit, 0] }, round: 0, dealer: nil, phase: :awaiting_deal,
        hands: players.to_h { |player| [player, []] }, current_player: nil, winner: nil, draw: false,
        deal_group: 0, play_count: 0}
    end

    def deal_recipe(state)
      dealer = state[:dealer] ? (state[:dealer] + 1) % state[:seats].size : '{dealer}'
      ["#{state[:round] + 1}|#{dealer}|{seed}", (0...state[:seats].size).to_a]
    end

    def apply_replay_event(state, event, session, repository, history)
      actor = repository.actor_of(event, session)
      case event['action']
      when 'deal'
        return false unless same_user?(actor, state[:players].first) && [:awaiting_deal, :round_complete].include?(state[:phase])
        return false unless valid_roster?(state)
        begin
          round, dealer, seed = GameRoomCardWire.parse_deal(event['value'])
        rescue ArgumentError
          return false
        end
        return false unless round == state[:round] + 1 && dealer.between?(0, state[:seats].size - 1)
        expected = state[:dealer] ? (state[:dealer] + 1) % state[:seats].size : seed.to_i(16) % state[:seats].size
        template, seats = deal_recipe(state)
        return false unless dealer == expected && GameRoomServerRandom.valid_text_seed_event?(event, template: template, seats: seats)
        state[:round], state[:dealer], state[:deal_group] = round, dealer, 0
        deal_round(state, seed, event, repository, history)
        true
      when 'play'
        return false unless state[:phase] == :playing && same_user?(actor, state[:current_player])
        card = event['value']
        hand = hand_for(state, actor)
        return false unless hand.include?(card)
        return false unless state[:private_cards] || legal_cards(state, actor).include?(card)
        hand.delete(card)
        state[:play_count] += 1
        add_history(history, event, repository, :play, _("%{player} plays %{card}.") % {
          player: participant_name(actor), card: playing_card_label(card)}, actor: actor, value: card)
        play_card(state, actor, card, event, repository, history)
        true
      else apply_extra_card_event(state, event, session, repository, history)
      end
    end

    def apply_extra_card_event(_state, _event, _session, _repository, _history); false; end

    def legal_cards(state, actor); hand_for(state, actor); end
    def valid_roster?(state)
      players = state[:players]
      players.size.between?(minimum_players, maximum_players) && GameRoomParticipants.unique(players).size == players.size &&
        validation_error(state[:options], player_count: players.size).nil?
    end
    def hand_for(state, actor)
      state[:hands].find { |player, _| same_user?(player, actor) }&.last || []
    end
    def unit_for(state, actor)
      state[:unit_for].find { |player, _| same_user?(player, actor) }&.last
    end
    def next_player(state, player)
      index = player_index(state[:seats], player)
      state[:seats][(index + 1) % state[:seats].size]
    end
    def first_player(state); state[:seats][(state[:dealer] + 1) % state[:seats].size]; end
    def unit_label(state, unit)
      state[:players].select { |player| state[:unit_for][player] == unit }.map { |player| participant_name(player) }.join(' / ')
    end
    def cards_text(cards); cards.map { |card| playing_card_label(card) }.join(', '); end
    def scores_text(state)
      state[:units].sort_by { |unit| score_order == 'lower' ? state[:scores][unit] : -state[:scores][unit] }.
        map { |unit| "#{unit_label(state, unit)}: #{state[:scores][unit]}" }.join("\n")
    end
    def table_information_text(state)
      cards = table_cards(state)
      cards.empty? ? _("No cards on the table") : cards_text(cards)
    end
    def round_information_text(state)
      table_information_text(state)
    end

    def winning_units(state)
      best = score_order == 'lower' ? state[:scores].values.min : state[:scores].values.max
      state[:units].select { |unit| state[:scores][unit] == best }
    end
    def finish_game(state, event, repository, history)
      winners = winning_units(state)
      state[:phase], state[:current_player] = :finished, nil
      state[:winner], state[:draw] = winners.size == 1 ? [winners.first, false] : [nil, true]
      replay = Replay.new(players: state[:players], state: state, winner: state[:winner], draw: state[:draw])
      add_history(history, event, repository, :result, "#{result_text(replay)}\n#{scores_text(state)}")
    end
    def add_history(history, event, repository, kind, text, actor: '', value: nil)
      eid = repository.event_id(event)
      history << HistoryEntry.new(key: "#{id}:#{eid}:#{kind}:#{history.size}", event_id: eid,
        actor: actor, kind: kind, text: text, value: value)
    end
  end
end
