require_relative "../dealt_card_game"
require_relative "../../lib/private_card_round_audit"
require_relative "jass_cards"
require_relative "jass_bot"

GameRoomServerRandom.register('jass', ['deal'])
GameRoomPrivateCards.register('jass', host: %w[private_deal], claim: %w[private_ready choose_trump],
  take: %w[initial_hand], reveal: %w[play], random: %w[deal])

module GameRoomGames
  # Shared table adapter. Register the game only once bidding and the private
  # round audit are connected; the base class alone handles single-card turns.
  class JassTable < DealtCardGame
    def id; "jass"; end
    def name; "Jass"; end
    def private_table_required?(_options); true; end
    def short_description; "Szwajcarska gra w lewy dla dw\u00f3ch dru\u017cyn."; end

    def rule_sections; generated_rule_sections; end
    def minimum_players; 4; end
    def maximum_players; 4; end
    def team_size(_options, player_count:); player_count == 4 ? 2 : 0; end

    TRUMP_LABELS = {
      'clubs' => 'Trefl', 'diamonds' => 'Karo', 'hearts' => 'Kier',
      'spades' => 'Pik', 'high' => 'Obenabe', 'low' => 'Undenufe', 'pass' => "Przeka\u017c wyb\u00f3r partnerowi"
    }.freeze

    def option_definitions
      [
        OptionDefinition.new(key: "variant", label: "Wariant", kind: :choice, default: "playroom", choices: [
          OptionChoice.new(value: "playroom", label: "Z atutem"),
          OptionChoice.new(value: "schieber", label: "Schieber z trybami bez atutu")
        ]),
        OptionDefinition.new(key: "score_limit", label: "Cel punktowy", kind: :choice, default: "1000",
          choices: %w[1000 1500 2000 2500].map { |points| OptionChoice.new(value: points, label: points) })
      ]
    end

    def shortcut_features
      super + [:led_suit, :statistics]
    end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      case feature
      when :led_suit
        lead = table_cards(state).first
        suit = JassCards.decode(lead).first if lead
        message = round_information_text(state)
        message += " Kolor wyj\u015bcia: #{TRUMP_LABELS.fetch(suit.to_s)}." if suit
        {message: message}
      when :statistics
        points = state.fetch(:round_points, {})
        message = state.fetch(:units).map do |unit|
          "#{GameRoomContent.utf8(unit_label(state, unit))}: #{points.fetch(unit, 0)}"
        end.join(". ")
        {label: "Punkty rozdania", message: message}
      else
        super
      end
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = super
      shortcuts << announcement_shortcut(key: "r", label: "Odczytaj zasady rozdania", message: round_information_text(replay.state))
      return shortcuts unless replay.state[:phase] == :choosing_trump && same_user?(replay.current_player, viewer)

      choices = trump_choices(replay.state).map do |choice|
        ShortcutChoice.new(value: choice.to_s, label: TRUMP_LABELS.fetch(choice.to_s))
      end
      %w[b enter].each do |key|
        shortcuts << GameShortcut.new(key: key, kind: :choice, label: "Wybierz zasady rozdania",
          prompt: "Wybierz atut lub inny dost\u0119pny tryb", choices: choices,
          action_kind: "command", action_name: "choose_trump", value_key: "choice")
      end
      shortcuts
    end

    def move_error(status)
      return "Do\u0142\u00f3\u017c do koloru albo zagraj dozwolony atut. Ni\u017cszy atut mo\u017cesz zagra\u0107 tylko wtedy, gdy nie masz innego legalnego ruchu." if status == :must_follow_suit

      super
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      cues = Array(super)
      trump = before_replay&.state&.fetch(:trump, nil)
      card = JassCards::DECODED[event["value"]]
      if event["action"] == "play" && trump && card&.first == trump && history.any? { |entry| entry.kind == :play }
        cues << "draw2"
      end
      cues
    end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      if action['action'] == 'choose_trump'
        hand = hand_for(state, actor).compact.map { |card| JassCards.decode(card) }
        preferred = JassBot.bid(bids: trump_choices(state), hand: hand)
        return action['choice'] == preferred.to_s ? 1 : 0
      end
      return 0 unless action['kind'] == 'card'
      legal = legal_cards(state, actor).map { |card| JassCards.decode(card) }
      trick = table_cards(state).map { |card| JassCards.decode(card) }
      preferred = JassBot.play(legal_cards: legal, trick: trick, trump: state[:trump])
      preferred && action['card'] == JassCards.encode(preferred) ? 1 : 0
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return super unless state[:phase] == :choosing_trump
      return [] if replay.finished? || !same_user?(state[:current_player], actor)

      trump_choices(state).map do |choice|
        {'kind' => 'command', 'action' => 'choose_trump', 'choice' => choice.to_s}
      end
    end

    def action_for(selection, replay, actor, context: nil)
      return super unless selection['action'] == 'choose_trump'
      return [:invalid, nil] unless legal_actions(replay, actor).any? { |command| command.all? { |key, value| selection[key] == value } }

      choice = selection['choice']
      plan = event_plan('choose_trump', choice)
      return private_secure_plan(plan, replay.state, actor) if replay.state[:private_cards]
      [:ok, plan]
    end

    protected

    def apply_extra_card_event(state, event, session, repository, history)
      return super unless event['action'] == 'choose_trump'
      return false unless state[:phase] == :choosing_trump
      actor = repository.actor_of(event, session)
      return false unless same_user?(state[:current_player], actor)
      value = event['value']
      choice = trump_choices(state).find { |option| option.to_s == value }
      return false unless choice

      if choice == :pass
        seat = player_index(state[:seats], actor)
        state[:current_player] = state[:seats][(seat + 2) % 4]
        name = GameRoomContent.utf8(participant_name(actor))
        add_history(history, event, repository, :trump,
          "#{name} przekazuje wyb\u00f3r partnerowi. #{round_information_text(state)}", actor: actor)
      else
        state[:trump] = choice
        state[:trump_chooser] = actor
        state[:phase] = :playing
        state[:current_player] = first_player(state)
        add_history(history, event, repository, :trump, round_information_text(state), actor: actor)
      end
      true
    end

    def trump_choices(state)
      choices = JassRound::SUITS
      choices += %i[high low] if state.fetch(:options, {})["variant"] == "schieber"
      same_user?(state[:current_player], first_player(state)) ? choices + [:pass] : choices
    end

    def deal_round(state, seed, event, repository, history)
      seats = state.fetch(:seats)
      state[:hands] = seats.to_h { |seat| [seat, []] }
      if state[:private_cards]
        state[:hands].each_value { |hand| hand.concat(Array.new(9)) }
      else
        shuffled_cards(JassCards::DECK, seed).each_with_index do |card, index|
          state[:hands].fetch(seats[index % 4]) << card
        end
      end
      state[:trick] = []
      state[:play_count] = 0
      state[:round_points] = state[:units].to_h { |unit| [unit, 0] }
      state[:trump] = nil
      state[:trump_chooser] = nil
      state[:phase] = :choosing_trump
      state[:current_player] = first_player(state)
      add_history(history, event, repository, :trump, round_information_text(state), actor: state[:current_player]) unless state[:private_cards]
    end

    def private_dealing_applied(state, event, _session, repository, history)
      add_history(history, event, repository, :trump, round_information_text(state), actor: state[:current_player])
    end

    def round_information_text(state)
      if state[:phase] == :choosing_trump && state[:current_player]
        name = GameRoomContent.utf8(participant_name(state[:current_player]))
        return "#{name} wybiera zasady rozdania. W swojej kolejce naci\u015bnij B lub Enter."
      end
      mode = state[:trump]
      return "Nie wybrano jeszcze zasad rozdania." unless mode

      chooser = GameRoomContent.utf8(participant_name(state[:trump_chooser]))
      label = TRUMP_LABELS.fetch(mode.to_s)
      rules = %i[high low].include?(mode) ? "#{label}, bez atutu" : "atut #{label}"
      "#{chooser} wybiera #{rules}."
    end

    def table_cards(state)
      state.fetch(:trick, []).map(&:last)
    end

    def legal_cards(state, actor)
      return [] unless state[:phase] == :playing && same_user?(state[:current_player], actor)

      hand = hand_for(state, actor).compact.map { |card| JassCards.decode(card) }
      trick = table_cards(state).map { |card| JassCards.decode(card) }
      JassRound.legal(hand, trick, state.fetch(:trump)).map { |card| JassCards.encode(card) }
    end

    def play_card(state, actor, card, event, repository, history)
      trick = state.fetch(:trick)
      trick << [actor, card]
      if trick.size < 4
        state[:current_player] = next_player(state, actor)
        return
      end

      last = state[:play_count] == 36
      index, points = JassRound.settle_trick(trick.map { |_, value| JassCards.decode(value) }, state[:trump], last: last)
      winner = trick.fetch(index).first
      state.fetch(:scores)[unit_for(state, winner)] += points
      round_points = state[:round_points] ||= Hash.new(0)
      round_points[unit_for(state, winner)] += points
      name = GameRoomContent.utf8(participant_name(winner))
      message = "#{name} bierze lew\u0119 za #{points} pkt."
      message += " Wychodzi do nast\u0119pnej lewy." unless last
      add_history(history, event, repository, :trick, message, actor: winner) if repository
      trick.clear
      state[:current_player] = last ? nil : winner
      return unless last

      if state[:private_cards]
        state[:phase] = :private_round_end
        return
      end

      if repository && state[:units]
        state[:units].each do |unit|
          name = GameRoomContent.utf8(unit_label(state, unit))
          add_history(history, event, repository, :round_result,
            "#{name}. Punkty rozdania: #{round_points.fetch(unit, 0)}. Wynik meczu: #{state[:scores].fetch(unit)}.")
        end
      end
      if state[:scores].respond_to?(:values) && state[:scores].values.max >= state.fetch(:options, {}).fetch("score_limit", 1000).to_i
        finish_game(state, event, repository, history)
      else
        state[:phase] = :round_complete
      end
    end

    def private_after_event(state, event, session, repository, history)
      state.fetch(:private_round_actions) << event
      return unless state[:phase] == :private_round_end

      audit = GameRoomPrivateCardRoundAudit.initial_state(state)
      audited_history = []
      verified = audit && state.fetch(:private_round_actions).all? do |record|
        apply_replay_event(audit, record, session, repository, audited_history)
      end
      if verified
        state.merge!(audit)
        history.concat(audited_history.select { |entry| %i[round_result result].include?(entry.kind) })
      else
        GameRoomPrivateCardRoundAudit.reject_round(state, event, repository, history)
      end
    end

    def private_deal_spec(state)
      GameRoomPrivateCardRoundAudit.begin_round(state)
      {hands: state.fetch(:hands), deck: JassCards::DECK}
    end
  end
end

require_relative '../generated/rulebooks/jass'
