require_relative 'dealt_card_game'
require_relative '../lib/private_card_round_audit'

GameRoomServerRandom.register('bouillabaisse', ['deal'])
GameRoomPrivateCards.register('bouillabaisse', host: %w[private_deal], claim: %w[private_ready],
  take: %w[initial_hand], reveal: %w[play], random: %w[deal])

module GameRoomGames
  class Bouillabaisse < DealtCardGame
    using GameRoomLocalization::Translations

    def id; 'bouillabaisse'; end
    def name; 'Bouillabaisse'; end
    def maximum_players; 8; end
    def short_description
      _("Avoid taking penalty cards over six rounds, then recover points in the final round.")
    end

    def option_definitions
      [OptionDefinition.new(key: 'all_or_nothing', label: _("All or nothing: taking every scoring item reverses your round score"),
        kind: :boolean, default: true)]
    end

    def options_summary(options)
      normalize_options(options)['all_or_nothing'] ? _("Six rounds, all or nothing") : _("Six rounds")
    end
    def notification_option_keys(_options); %w[all_or_nothing]; end
    def notification_variant(options)
      notification_flag(options, 'all_or_nothing', _("All or nothing"), _("Without all or nothing")).to_s
    end

    def bot_strategy; @bot_strategy ||= BouillabaisseStrategy.new; end
    def bot_observation(replay, actor)
      state = replay.state
      {'hand' => hand_for(state, actor).dup, 'trick' => state[:trick].to_a.map(&:dup),
        'round' => state[:round], 'penalties' => (state[:penalties] || {}).dup,
        'seats' => state[:seats].dup, 'actor' => actor}
    end

    def shortcut_features; super + [:led_suit]; end
    def custom_game_shortcuts(replay, viewer)
      super + [GameShortcut.new(key: 'r', kind: :announcement, label: _("read the rules for this round"),
        message: round_information_text(replay.state))]
    end
    def shortcut_feature_data(feature, replay, viewer)
      if feature == :table_cards_list && replay.state[:trick].to_a.any?
        return {kind: :browse, prompt: _("Cards on the table"), choices: replay.state[:trick].map do |player, card|
          ShortcutChoice.new(value: card, label: _("%{player}: %{card}") % {
            player: participant_name(player), card: playing_card_label(card)})
        end}
      end
      return super unless feature == :led_suit
      first = replay.state[:trick].to_a.first
      {message: first ? suit_label(playing_card_suit(first.last)) : _("No cards on the table")}
    end

    # A single standard deck, with only enough low cards removed to deal evenly.
    def deck_for(player_count)
      deck = standard_deck.sort_by { |card| [CARD_RANKS.index(card[0]), CARD_SUITS.index(card[1])] }
      deck.drop(deck.size % player_count)
    end

    def penalty_value(card, round, penalties)
      value = 0
      value += 10 if [2, 5, 6].include?(round) && card[1] == penalties['suit']
      value += 50 if [3, 5, 6].include?(round) && card[0] == penalties['rank']
      value += 200 if [4, 5, 6].include?(round) && card == penalties['card']
      value
    end

    protected

    def hand_cards_for_display(hand)
      hand.sort_by do |card|
        standard_hand_sort_keys(rank: playing_card_rank(card), suit: playing_card_suit(card), position: 0).fetch('colour')
      end
    end

    def score_order; 'lower'; end
    def table_cards(state); state[:trick].to_a.map(&:last); end
    def table_information_text(state)
      return super if state[:trick].to_a.empty?
      state[:trick].map do |player, card|
        _("%{player}: %{card}") % {player: participant_name(player), card: playing_card_label(card)}
      end.join("\n")
    end

    def legal_cards(state, actor)
      hand = hand_for(state, actor)
      led = state[:trick].to_a.first&.last&.[](1)
      suited = hand.select { |card| card[1] == led }
      suited.empty? ? hand : suited
    end

    def deal_round(state, seed, event, repository, history)
      deck = deck_for(state[:players].size)
      unless state[:penalties]
        random = Random.new(seed.to_i(16))
        state[:penalties] = {'suit' => CARD_SUITS[random.rand(4)], 'rank' => %w[J Q K][random.rand(3)],
          'card' => deck[random.rand(deck.size)]}
      end
      state[:round_deck] = deck
      state[:hands] = state[:players].to_h { |player| [player, []] }
      count = deck.size / state[:players].size
      if state[:private_cards]
        state[:hands].each_value { |hand| hand.concat(Array.new(count)) }
      else
        shuffled_cards(deck, seed).each_with_index do |card, index|
          state[:hands][state[:seats][(state[:dealer] + 1 + index) % state[:seats].size]] << card
        end
      end
      state[:trick] = []
      state[:taken] = state[:players].to_h { |player| [player, []] }
      state[:tricks] = state[:players].to_h { |player| [player, 0] }
      state[:phase], state[:current_player] = :playing, first_player(state)
      add_history(history, event, repository, :deal, round_information_text(state))
    end

    def private_deal_spec(state)
      GameRoomPrivateCardRoundAudit.begin_round(state)
      {hands: state[:hands], deck: state[:round_deck]}
    end

    def private_after_event(state, event, session, repository, history)
      state[:private_round_actions] << event
      return unless state[:phase] == :private_round_end
      # A scoring round may end while cards remain in hands. Reveal those
      # receipts through the shared path before auditing the complete deal.
      return if GameRoomPrivateCardDisclosure.prepare(state, state[:players], purpose: 'round-audit')
      state.delete(:private_disclosure)
      audit_private_round(state, event, session, repository, history)
    end

    def private_disclosure_completed(state, purpose, event, session, repository, history)
      audit_private_round(state, event, session, repository, history) if purpose == 'round-audit'
    end

    def audit_private_round(state, event, session, repository, history)
      audit = GameRoomPrivateCardRoundAudit.initial_state(state)
      audit_history = []
      valid = audit && state[:private_round_actions].all? do |item|
        apply_replay_event(audit, item, session, repository, audit_history)
      end
      unless valid
        GameRoomPrivateCardRoundAudit.reject_round(state, event, repository, history)
        return
      end
      state.merge!(audit)
      audit_history.select { |entry| [:score, :result].include?(entry.kind) }.each do |entry|
        entry.event_id = repository.event_id(event)
        history << entry
      end
    end

    def play_card(state, actor, card, event, repository, history)
      state[:trick] << [actor, card]
      if state[:trick].size < state[:players].size
        state[:current_player] = next_player(state, actor)
        return
      end
      led = state[:trick].first.last[1]
      winner = state[:trick].select { |_, value| value[1] == led }.max_by { |_, value| CARD_RANKS.index(value[0]) }.first
      state[:tricks][winner] += 1
      state[:taken][winner].concat(table_cards(state))
      state[:trick] = []
      add_history(history, event, repository, :trick, _("%{player} wins the trick.") % {player: participant_name(winner)}, actor: winner)
      state[:current_player] = winner
      if round_scoring_complete?(state)
        if state[:private_cards]
          state[:phase], state[:current_player] = :private_round_end, nil
        else
          score_round(state, event, repository, history)
        end
      end
    end

    def round_scoring_complete?(state)
      return true if state[:hands].values.all?(&:empty?)
      # Rounds 1, 5 and 6 score every trick, so unplayed tricks still matter.
      return false unless [2, 3, 4].include?(state[:round])
      remaining = state[:round_deck] - state[:taken].values.flatten
      remaining.none? { |card| penalty_value(card, state[:round], state[:penalties]).positive? }
    end

    def score_round(state, event, repository, history)
      round = state[:round]
      raw = state[:players].to_h do |player|
        tricks = [1, 5, 6].include?(round) ? state[:tricks][player] * 5 : 0
        [player, tricks + state[:taken][player].sum { |card| penalty_value(card, round, state[:penalties]) }]
      end
      total = raw.values.sum
      additions = raw.to_h do |player, value|
        value = -value if state[:options]['all_or_nothing'] && round != 4 && value == total && total.positive?
        [player, round == 6 ? -value : value]
      end
      additions.each { |player, value| state[:scores][player] += value }
      state[:phase], state[:current_player] = :round_complete, nil
      add_history(history, event, repository, :score, _("Round scores: %{scores}.") % {
        scores: additions.map { |player, value| "#{participant_name(player)}: #{value}" }.join("\n")})
      remember_tournament_checkpoint(state, event_id: repository.event_id(event), index: round, order: 'lower')
      finish_game(state, event, repository, history) if round == 6
    end

    def suit_label(suit)
      {'C' => _("clubs"), 'D' => _("diamonds"), 'H' => _("hearts"), 'S' => _("spades")}.fetch(suit)
    end

    def round_information_text(state)
      return _("Waiting for the deal.") if state[:round].zero?
      penalties = state[:penalties]
      rules = if state[:round] == 6
        [_('Each trick you take subtracts 5 points from your score.'),
          _('Each card of %{suit} you take subtracts 10 points.') % {suit: suit_label(penalties['suit'])},
          {'J' => _('Each jack you take subtracts 50 points.'),
            'Q' => _('Each queen you take subtracts 50 points.'),
            'K' => _('Each king you take subtracts 50 points.')}.fetch(penalties['rank']),
          _('Taking %{card} subtracts 200 points.') % {card: playing_card_label(penalties['card'])}]
      else
        costs = [_('Each trick costs 5 points.'),
          _('Each card of %{suit} costs 10 points.') % {suit: suit_label(penalties['suit'])},
          {'J' => _('Each jack you take costs 50 points.'),
            'Q' => _('Each queen you take costs 50 points.'),
            'K' => _('Each king you take costs 50 points.')}.fetch(penalties['rank']),
          _('Taking %{card} costs 200 points.') % {card: playing_card_label(penalties['card'])}]
        state[:round] == 5 ? costs : [costs.fetch(state[:round] - 1)]
      end
      _("Round %{round} of 6. %{rule}") % {round: state[:round], rule: rules.join("\n")}
    end

  end

  class BouillabaisseStrategy
    include GameRoomBots::ReplayOnlyStrategy
    def choose(actions:, observation:, **_extra)
      cards = actions.to_a
      return nil if cards.empty?
      trick = observation['trick']
      rank = ->(card) { CardGame::CARD_RANKS.index(card[0]) }
      winning = trick.empty? ? nil : trick.select { |_, card| card[1] == trick.first.last[1] }.max_by { |_, card| rank.call(card) }.last
      lose = cards.select { |action| winning && (action['card'][1] != winning[1] || rank.call(action['card']) < rank.call(winning)) }
      candidates = observation['round'] == 6 ? cards : (lose.empty? ? cards : lose)
      candidates.min_by do |action|
        card = action['card']
        # Only the current public trick and this bot's own legal hand are used.
        observation['round'] == 6 ? -rank.call(card) : (lose.empty? ? rank.call(card) : -rank.call(card))
      end
    end
  end
end

require_relative 'generated/rulebooks/bouillabaisse'
