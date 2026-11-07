require_relative 'dealt_card_game'
require_relative '../lib/scopa_strategy'

GameRoomServerRandom.register('scopa', ['deal'])
GameRoomPrivateCards.register('scopa', host: %w[private_deal], claim: %w[private_ready],
  take: %w[initial_hand private_draw], reveal: %w[play], random: %w[deal])

module GameRoomGames
  class Scopa < DealtCardGame
    using GameRoomLocalization::Translations
    RANKS = %w[A 2 3 4 5 6 7 8 9 T].freeze
    DECK = CardGame::CARD_SUITS.flat_map { |suit| RANKS.map { |rank| "#{rank}#{suit}" } }.freeze

    def id; 'scopa'; end
    def name; 'Scopa'; end
    def maximum_players; 6; end
    def short_description
      _("Capture cards by matching their values, and clear the table for extra points.")
    end

    def option_definitions
      [
        OptionDefinition.new(key: 'score_limit', label: _("Score limit"), kind: :integer, default: 11),
        OptionDefinition.new(key: 'two_point_lead', label: _("Win by two points: reach the target and lead by at least two"), kind: :boolean, default: true),
        OptionDefinition.new(key: 'team_size', label: _("Team arrangement"), kind: :choice, default: 0,
          choices: [OptionChoice.new(value: 0, label: _("Individual play")),
            OptionChoice.new(value: 2, label: _("Teams of two")), OptionChoice.new(value: 3, label: _("Teams of three"))]),
        OptionDefinition.new(key: 'escoba', label: _("Escoba: your card and the captured cards must add up to 15"), kind: :boolean, default: false),
        OptionDefinition.new(key: 'scopone', label: _("Scopone: an empty table and larger hands instead of three-card deals"), kind: :boolean, default: false),
        OptionDefinition.new(key: 'muerto', label: _("Muerto: each point you earn goes to every opponent instead"), kind: :boolean, default: false)
      ]
    end

    def team_size(options, player_count:); normalize_options(options)['team_size']; end
    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _("The score limit must be greater than zero.") unless values['score_limit'].positive?
      size = values['team_size']
      return _("Teams of two require four or six players.") if size == 2 && player_count && ![4, 6].include?(player_count)
      return _("Teams of three require exactly six players.") if size == 3 && player_count && player_count != 6
      nil
    end

    def options_summary(options)
      values = normalize_options(options)
      selected = []
      selected << _("Escoba") if values['escoba']
      selected << _("Scopone") if values['scopone']
      selected << _("Muerto") if values['muerto']
      selected << _("Standard") if selected.empty?
      selected << notification_points(values, 'score_limit')
      selected << _("win by two") if values['two_point_lead']
      selected.join(', ')
    end
    def notification_option_keys(_options); %w[escoba scopone muerto score_limit]; end
    def notification_variant(options)
      variants = []
      variants << _("Escoba") if options['escoba'] == true
      variants << _("Scopone") if options['scopone'] == true
      variants << _("Muerto") if options['muerto'] == true
      if %w[escoba scopone muerto].all? { |key| options[key] == false }
        variants << p_("scopa variant", "Classic")
      end
      [*variants, notification_points(options, 'score_limit')].compact.join(', ')
    end

    def bot_strategy; @bot_strategy ||= ScopaStrategy.new; end
    def bot_observation(replay, actor)
      state = replay.state
      return {} unless state[:phase] == :playing

      {'hand' => hand_for(state, actor).dup, 'table' => state[:table].to_a.dup,
        'seat' => player_index(state[:seats], actor),
        'units' => state[:seats].map { |player| state[:unit_for].fetch(player) },
        'counts' => state[:seats].map { |player| state[:hands].fetch(player).size },
        'taken' => state[:taken].transform_values(&:dup), 'scopas' => state[:scopas].dup,
        'last_capturer' => state[:last_capturer], 'scores' => state[:scores].dup,
        'stock_count' => state[:stock].size, 'discard_count' => state[:discarded].size,
        'score_limit' => state[:options]['score_limit'], 'two_point_lead' => state[:options]['two_point_lead'],
        'escoba' => state[:options]['escoba'], 'muerto' => state[:options]['muerto']}
    end

    def self.card_value(card); card[0] == 'A' ? 1 : card[0] == 'T' ? 10 : card[0].to_i; end

    # At most 15 sums, rather than enumerating every subset of a large table.
    # Prefer the fewest cards, then the earliest cards in table order.
    def self.capture(table, card, escoba: false)
      target = escoba ? 15 - card_value(card) : card_value(card)
      return [] unless target.positive?
      best = {0 => []}
      table.each_with_index do |item, index|
        value = card_value(item)
        target.downto(value) do |sum|
          prefix = best[sum - value]
          next unless prefix
          candidate = prefix + [index]
          old = best[sum]
          if !old || ([candidate.size, candidate] <=> [old.size, old]).negative?
            best[sum] = candidate
          end
        end
      end
      best.fetch(target, []).map { |index| table[index] }
    end

    def self.round_awards(taken)
      awards = {cards: ->(cards) { cards.size }, diamonds: ->(cards) { cards.count { |card| card[1] == 'D' } },
        sevens: ->(cards) { cards.count { |card| card[0] == '7' } }}.transform_values do |metric|
        counts = taken.transform_values { |cards| metric.call(cards) }
        leaders = counts.keys.select { |unit| counts[unit] == counts.values.max }
        leaders.first if leaders.size == 1
      end
      awards.merge(seven_diamonds: taken.keys.find { |unit| taken[unit].include?('7D') })
    end

    # Scoring and its explanation share the same awards. A team is one side.
    def self.round_points(taken, scopas, muerto: false, awards: round_awards(taken))
      raw = scopas.dup
      awards.each_value { |unit| raw[unit] += 1 if unit }
      muerto ? raw.to_h { |unit, _| [unit, raw.values.sum - raw[unit]] } : raw
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      cues = Array(super).map { |cue| cue == 'shuffle' ? 'scopa_deal' : cue }
      cues << 'scopa_take' if history.any? { |entry| entry.kind == :take }
      cues << 'scopa' if history.any? { |entry| entry.kind == :scopa }
      cues
    end

    protected

    def standard_hand_sort_keys(rank:, suit:, position:)
      suit_index = PLAYROOM_SUIT_ORDER.index(suit) || PLAYROOM_SUIT_ORDER.size
      rank_index = RANKS.index(rank) || RANKS.size
      {'colour' => [suit_index, rank_index], 'number' => [rank_index, suit_index], 'none' => [position]}
    end

    def table_cards(state); state[:table].to_a; end

    def deal_round(state, seed, event, repository, history)
      count = state[:players].size
      scopone = state[:options]['scopone']
      hand_size = scopone ? 40 / count : 3
      hand_size = 10 if scopone && count == 2
      opening = scopone ? 0 : count == 5 ? 5 : 4
      unused = scopone && count != 2 ? 40 % count : 0
      state[:table], state[:discarded] = [], []
      state[:taken] = state[:units].to_h { |unit| [unit, []] }
      state[:scopas] = state[:units].to_h { |unit| [unit, 0] }
      state[:last_capturer] = nil
      state[:hands] = state[:players].to_h { |player| [player, []] }
      if state[:private_cards]
        state[:hands].each_value { |hand| hand.concat(Array.new(hand_size)) }
        state[:stock] = Array.new(40 - count * hand_size - opening - unused)
        state[:private_opening] = {table: opening, discarded: unused}
      else
        state[:stock] = shuffled_cards(DECK, seed)
        state[:table] = state[:stock].shift(opening)
        state[:discarded] = state[:stock].pop(unused)
        deal_hands(state, hand_size)
      end
      state[:phase], state[:current_player] = :playing, first_player(state)
      add_history(history, event, repository, :deal, _("Deal %{round}.") % {round: state[:round]})
      announce_table(state, event, repository, history) unless state[:private_cards]
    end

    def private_deal_spec(state); {hands: state[:hands], deck: DECK}; end

    def private_dealing_applied(state, event, session, repository, history)
      return unless state[:phase] == :playing
      opening = state.delete(:private_opening)
      return unless opening
      count = opening.values.sum
      if count.positive?
        state[:private_opening_result] = opening
        private_request_draw(state, actor: state[:players].first, count: count, purpose: 'table', public: true)
      else
        announce_table(state, event, repository, history)
      end
    end

    def private_draw_completed(state, purpose, cards, event, session, repository, history)
      return super unless purpose == 'table'
      opening = state.delete(:private_opening_result)
      state[:table] = cards.first(opening[:table])
      state[:discarded] = cards.drop(opening[:table])
      announce_table(state, event, repository, history)
    end

    def announce_table(state, event, repository, history)
      add_history(history, event, repository, :table, table_information_text(state)) if state[:table].any?
    end

    def deal_hands(state, size)
      size.times do
        state[:seats].size.times do |index|
          player = state[:seats][(state[:dealer] + 1 + index) % state[:seats].size]
          state[:hands][player] << state[:stock].shift
        end
      end
    end

    def play_card(state, actor, card, event, repository, history)
      captured = self.class.capture(state[:table], card, escoba: state[:options]['escoba'])
      unit = unit_for(state, actor)
      if captured.empty?
        state[:table] << card
      else
        state[:table] -= captured
        state[:taken][unit].concat(captured + [card])
        state[:last_capturer] = unit
        add_history(history, event, repository, :take, _("%{player} captures %{cards}.") % {
          player: participant_name(actor), cards: cards_text(captured)}, actor: actor)
        if state[:table].empty?
          state[:scopas][unit] += 1
          add_history(history, event, repository, :scopa, _("Scopa!"), actor: actor)
        end
      end
      state[:current_player] = next_player(state, actor)
      return unless state[:hands].values.all?(&:empty?)
      if state[:stock].empty?
        score_round(state, event, repository, history)
      else
        state[:deal_group] += 1
        size = if state[:options]['scopone']
          10
        elsif state[:players].size == 5 && state[:stock].size == 20
          4
        else
          3
        end
        if state[:private_cards]
          count = size * state[:players].size
          state[:stock].shift(count)
          GameRoomPrivateCardDealing.append(state, state[:players].to_h { |player| [player, size] })
        else
          deal_hands(state, size)
        end
        if state[:stock].empty? && !state[:options]['scopone']
          add_history(history, event, repository, :last_deal, _("Final deal."))
        end
        add_history(history, event, repository, :redeal, _("New cards dealt."))
      end
    end

    def score_round(state, event, repository, history)
      if state[:last_capturer]
        state[:taken][state[:last_capturer]].concat(state[:table])
        state[:table] = []
      end
      awards = self.class.round_awards(state[:taken])
      additions = self.class.round_points(state[:taken], state[:scopas], muerto: state[:options]['muerto'], awards: awards)
      additions.each { |unit, value| state[:scores][unit] += value }
      state[:phase], state[:current_player] = :round_complete, nil
      add_history(history, event, repository, :score_breakdown, round_award_lines(state, awards).join("\n"))
      add_history(history, event, repository, :score, _("Round scores: %{scores}.") % {
        scores: additions.map { |unit, value| "#{unit_label(state, unit)}: #{value}" }.join("\n")})
      remember_tournament_checkpoint(state, event_id: repository.event_id(event), index: state[:round])
      ordered = state[:scores].values.sort.reverse
      reached = ordered.first >= state[:options]['score_limit']
      lead = !state[:options]['two_point_lead'] || ordered.first - ordered[1] >= 2
      finish_game(state, event, repository, history) if reached && lead && ordered.first > ordered[1]
    end

    def round_award_lines(state, awards)
      lines = if state[:options]['muerto']
        awards.filter_map do |kind, unit|
          next unless unit
          opponents = state[:units].reject { |other| other == unit }
          source = case kind
          when :cards; _("%{player} has the most cards.")
          when :diamonds; _("%{player} has the most diamonds.")
          when :sevens; _("%{player} has the most sevens.")
          when :seven_diamonds; _("%{player} has the seven of diamonds.")
          end
          recipients = n_("%{players} receives 1 point.", "%{players} receive 1 point each.", opponents.size) % {
            players: opponents.map { |other| unit_label(state, other) }.join(', ')}
          "#{source % {player: unit_label(state, unit)}} #{recipients}"
        end
      else
        state[:units].filter_map do |unit|
          bonuses = awards.filter_map do |kind, winner|
            next unless winner == unit
            case kind
            when :cards; _("1 point for the most cards")
            when :diamonds; _("1 point for the most diamonds")
            when :sevens; _("1 point for the most sevens")
            when :seven_diamonds; _("1 point for the seven of diamonds")
            end
          end
          next if bonuses.empty?
          _("%{player}: %{bonuses}.") % {player: unit_label(state, unit), bonuses: bonuses.join(', ')}
        end
      end
      lines << _("Most cards: tied, no point.") unless awards[:cards]
      lines << _("Most diamonds: tied, no point.") unless awards[:diamonds]
      lines << _("Most sevens: tied, no point.") unless awards[:sevens]
      lines
    end

    def round_information_text(state)
      _("Deal %{round}. Cards left to deal: %{count}.") % {round: state[:round], count: state.fetch(:stock, []).size}
    end
  end

end

require_relative 'generated/rulebooks/scopa'
