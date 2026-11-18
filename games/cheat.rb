require_relative 'card_game'
require_relative '../lib/game_bots'

GameRoomServerRandom.register('cheat', ['cheat_deal'])

module GameRoomGames
  using GameRoomLocalization::Translations

  class Cheat < CardGame
    include PublicHistoryAnnouncements

    VARIANTS = %w[ascending descending neighbour fixed_bluff suit].freeze
    RANKS = %w[A 2 3 4 5 6 7 8 9 T J Q K].freeze
    CARD_HAND_ORDER = CardHandOrder.new(default_sort: 'colour', sort_modes: %w[colour number none],
      suits: %w[C D H S], ranks: %w[2 3 4 5 6 7 8 9 T J Q K A])

    def id; 'cheat'; end
    def name; _('Cheat'); end
    def short_description; _('Shed your cards by declaring their rank or suit, and decide when to challenge a bluff.'); end
    def minimum_players; 2; end
    def maximum_players; 8; end
    def maximum_players_for_options(options); normalize_options(options)['variant'] == 'fixed_bluff' ? 6 : 8; end
    def supports_bots?; true; end
    def session_history_capacity(_options); 32_768; end
    def serial_event_presentation?; true; end
    def rule_sections; generated_rule_sections; end

    def variant_choices
      [OptionChoice.new(value: 'ascending', label: _('Classic: ascending ranks')),
       OptionChoice.new(value: 'descending', label: _('Descending ranks')),
       OptionChoice.new(value: 'neighbour', label: _('Same or neighbouring rank')),
       OptionChoice.new(value: 'fixed_bluff', label: _('Bluff: fixed pile rank')),
       OptionChoice.new(value: 'suit', label: _('Suit: single cards'))]
    end

    def option_definitions
      [OptionDefinition.new(key: 'variant', label: _('Variant'), kind: :choice,
        default: 'ascending', choices: variant_choices)]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _('Unknown Cheat variant.') unless VARIANTS.include?(values['variant'])
      if player_count
        range = values['variant'] == 'fixed_bluff' ? (3..6) : (2..8)
        return _('Bluff requires 3 to 6 players.') if values['variant'] == 'fixed_bluff' && !range.cover?(player_count)
        return _('Cheat requires 2 to 8 players.') unless range.cover?(player_count)
      end
      bot_delay_options_error(values)
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session['options']))
      accepted, seen, history = [], {}, [starting_history(players)]
      events.each do |event|
        break if state[:winner]
        key = repository.event_id(event)
        next if seen[key]
        actor = repository.actor_of(event, session)
        applied = if event['action'] == 'cheat_deal'
          apply_deal(state, event, actor, key, history)
        else
          selection = event_selection(event)
          selection && validate_move(state, selection, actor) == :ok &&
            apply_move(state, selection, actor, key, history)
        end
        next unless applied
        seen[key] = true
        accepted << event
      end
      Replay.new(board: nil, players: players, current_player: state[:current_player],
        winner: state[:winner], draw: false, accepted_events: accepted, history: history, state: state)
    end

    def automatic_action(replay, actor, context: nil)
      return nil unless replay.state[:phase] == :awaiting_deal && same_user?(actor, replay.players.first)
      {'kind' => 'command', 'action' => 'cheat_deal'}
    end

    def automatic_action_due?(replay, actor, context: nil)
      automatic_action(replay, actor, context: context) != nil
    end

    def required_decision_key(replay, viewer)
      return nil unless super
      [replay.state[:phase], replay.state[:sequence], viewer.to_s.downcase]
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      state = replay.state
      if selection['kind'] == 'command' && selection['action'] == 'cheat_deal'
        return [:not_your_turn, nil] unless same_user?(actor, replay.players.first)
        return [:invalid, nil] unless state[:phase] == :awaiting_deal &&
          !options_error(state[:options], player_count: replay.players.length) && context&.random_source
        return [:ok, server_seed_plan('cheat_deal', template: '{dealer}|{seed}', seats: (0...replay.players.length).to_a)] if context.server_random
        seed = card_seed(context.random_source)
        return [:ok, event_plan('cheat_deal', "#{seed.to_i(16) % replay.players.length}|#{seed}")]
      end
      decoded = selection_data(selection)
      return [:invalid_packet, nil] unless decoded
      status = validate_move(state, decoded, actor)
      return [status, nil] unless status == :ok
      value = if decoded['action'] == 'play'
        "#{decoded['cards'].join(',')}|#{decoded['choice']}|#{decoded['boundary']}"
      else
        "#{decoded['packet']}|#{decoded['boundary']}"
      end
      [:ok, event_plan(decoded['action'], value)]
    end

    def participant_status(replay, participant, connected: true)
      hand = hand_for(replay.state, participant)
      return super if hand == nil
      [card_count_text(hand.length), super].compact.join('; ')
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      case event['action']
      when 'cheat_deal' then 'shuffle'
      when 'play' then 'play'
      when 'pass' then 'skip'
      when 'challenge'
        packet = before_replay.state[:last_packet]
        truthful = packet[:cards].all? { |card| matches_claim?(card, packet[:claim], before_replay.state[:options]['variant']) }
        cues = ['buzzer2', 'war_open', truthful ? 'quiz_wrong_answer' : 'win1', 'draw']
        stage = history.find { |entry| entry.kind == :cheat_challenge_stage }
        stage ? cues.fetch(stage.value) : cues
      end
    end

    def move_error(status)
      case status
      when :invalid_packet then _('Choose one to four different cards from your own hand; the suit variant requires one card.')
      when :invalid_claim then _('That declaration is unavailable in this variant or pile.')
      when :stale_packet then _('That play or reaction is no longer current.')
      else super
      end
    end

    private

    def initial_state(players, options)
      {players: players, options: normalize_options(options), phase: :awaiting_deal,
       hands: players.to_h { |player| [player, []] }, pile: [], removed: [], revealed: {},
       passed: [], last_packet: nil, last_claim: nil, last_author: nil,
       reaction_index: 0, reaction_order: [], current_player: nil, winner: nil, seed: nil, sequence: 0}
    end

    def hand_for(state, player)
      owner = state[:players].find { |candidate| same_user?(candidate, player) }
      state[:hands][owner] if owner
    end

    def apply_deal(state, event, actor, key, history)
      return false unless state[:phase] == :awaiting_deal && same_user?(actor, state[:players].first)
      return false if options_error(state[:options], player_count: state[:players].length)
      return false unless GameRoomServerRandom.valid_text_seed_event?(event,
        template: '{dealer}|{seed}', seats: (0...state[:players].length).to_a)
      match = /\A([0-7])\|([0-9a-f]{32})\z/.match(event['value'].to_s)
      return false unless match && match[1].to_i < state[:players].length
      deck = shuffled_cards(standard_deck, match[2])
      deck.each_with_index { |card, index| state[:hands].fetch(state[:players][index % state[:players].length]) << card }
      state.update(phase: :playing, current_player: state[:players][match[1].to_i], seed: match[2], sequence: 1)
      add_history(history, key, actor, :deal, _('All 52 cards were dealt.'))
      true
    end

    def selection_data(selection)
      action = selection['action']
      if action == 'play' && selection['kind'] == 'card_packet'
        cards = JSON.parse(selection['cards'].to_s)
        return nil unless cards.is_a?(Array) && cards.all? { |card| card.is_a?(String) }
        {'action' => action, 'cards' => cards, 'choice' => selection['choice'].to_s,
         'boundary' => selection['boundary'].to_s}
      elsif %w[challenge accept pass].include?(action) && selection['kind'] == 'command'
        {'action' => action, 'packet' => selection['packet'].to_s, 'boundary' => selection['boundary'].to_s}
      end
    rescue JSON::ParserError
      nil
    end

    def event_selection(event)
      fields = event['value'].to_s.split('|', -1)
      if event['action'] == 'play' && fields.length == 3
        {'action' => 'play', 'cards' => fields[0].split(',', -1), 'choice' => fields[1], 'boundary' => fields[2]}
      elsif %w[challenge accept pass].include?(event['action']) && fields.length == 2
        {'action' => event['action'], 'packet' => fields[0], 'boundary' => fields[1]}
      end
    end

    def validate_move(state, selection, actor)
      return :not_your_turn unless state[:current_player] && same_user?(state[:current_player], actor)
      return :stale_packet unless selection['boundary'] == state[:sequence].to_s(36)
      action = selection['action']
      if action == 'play'
        # Bluffing is legal; only a challenge checks the cards against the claim.
        return :invalid unless state[:phase] == :playing
        cards, hand = selection['cards'], hand_for(state, actor)
        maximum = state[:options]['variant'] == 'suit' ? 1 : 4
        return :invalid_packet unless cards.length.between?(1, maximum) && cards.uniq.length == cards.length &&
          cards.all? { |card| hand.include?(card) }
        return :invalid_claim unless allowed_claims(state).include?(selection['choice']) ||
          (state[:options]['variant'] == 'suit' && state[:pile].empty? && selection['choice'].empty?)
      elsif action == 'pass'
        return :invalid unless state[:phase] == :playing && state[:options]['variant'] == 'fixed_bluff' && !state[:pile].empty?
      elsif %w[challenge accept].include?(action)
        return :invalid unless state[:phase] == :reaction
        return :stale_packet unless selection['packet'] == state[:last_packet][:id].to_s(36)
      else
        return :invalid
      end
      :ok
    end

    def allowed_claims(state)
      previous = state[:last_claim]
      case state[:options]['variant']
      when 'ascending' then [previous ? RANKS[(RANKS.index(previous) + 1) % 13] : 'A']
      when 'descending' then [previous ? RANKS[(RANKS.index(previous) - 1) % 13] : 'A']
      when 'neighbour' then previous ? [-1, 0, 1].map { |offset| RANKS[(RANKS.index(previous) + offset) % 13] } : ['A']
      when 'fixed_bluff' then state[:pile].empty? ? RANKS.dup : [previous]
      when 'suit' then state[:pile].empty? ? [''] : [previous]
      end
    end

    def apply_move(state, selection, actor, key, history)
      state[:sequence] += 1
      actor = state[:current_player]
      case selection['action']
      when 'play' then apply_play(state, selection, actor, key, history)
      when 'accept'
        add_history(history, key, actor, :move, _('%{player} does not challenge this play.') % {player: participant_name(actor)})
        state[:reaction_index] += 1
        if state[:reaction_index] == state[:reaction_order].length
          close_reaction(state, key, history)
        else
          state[:current_player] = state[:reaction_order][state[:reaction_index]]
        end
      when 'challenge' then resolve_challenge(state, actor, key, history)
      when 'pass'
        state[:passed] << actor
        add_history(history, key, actor, :move, _('%{player} passes until this pile closes, but may still challenge.') % {player: participant_name(actor)})
        if state[:passed].length == state[:players].length
          state[:removed].concat(state[:pile])
          state[:pile].clear
          state[:passed].clear
          state[:last_claim] = nil
          state[:last_packet] = nil
          state[:current_player] = state[:last_author]
          add_history(history, key, actor, :move, _('Everyone passed. The pile is set aside face down.'))
        else
          state[:current_player] = next_unpassed(state, actor)
        end
      end
      true
    end

    def apply_play(state, selection, actor, key, history)
      cards = selection['cards']
      open_suit = state[:options]['variant'] == 'suit' && state[:pile].empty?
      claim = open_suit ? cards.first[1] : selection['choice']
      cards.each { |card| state[:hands].fetch(actor).delete(card) }
      state[:pile].concat(cards)
      state[:last_claim], state[:last_author] = claim, actor
      state[:last_packet] = {id: state[:sequence], actor: actor, cards: cards.dup, claim: claim}
      if open_suit
        state[:revealed][cards.first] = true
        add_history(history, key, actor, :move, _('%{player} opens face up with %{card}.') %
          {player: participant_name(actor), card: playing_card_label(cards.first)})
        finish_or_advance(state, actor, key, history)
      else
        add_history(history, key, actor, :move, _('%{player} declares %{declaration}. Pile: %{pile}.') %
          {player: participant_name(actor), declaration: declaration_text(claim, cards.length, state[:options]['variant']),
           pile: card_count_text(state[:pile].length)})
        state[:phase] = :reaction
        seat = state[:players].index(actor)
        state[:reaction_order] = (1...state[:players].length).map { |offset| state[:players][(seat + offset) % state[:players].length] }
        state[:reaction_index] = 0
        state[:current_player] = state[:reaction_order].first
      end
    end

    def close_reaction(state, key, history)
      author = state[:last_packet][:actor]
      state[:reaction_order] = []
      finish_or_advance(state, author, key, history)
    end

    def resolve_challenge(state, actor, key, history)
      packet = state[:last_packet]
      truth = packet[:cards].all? { |card| matches_claim?(card, packet[:claim], state[:options]['variant']) }
      recipient = truth ? actor : packet[:actor]
      count = state[:pile].length
      packet[:cards].each { |card| state[:revealed][card] = true }
      add_history(history, key, actor, :move, _('%{player} challenges. Revealed cards: %{cards}.') %
        {player: participant_name(actor), cards: packet[:cards].map { |card| playing_card_label(card) }.join('; ')})
      message = truth ? _('The declaration was true. %{player} takes %{cards}.') : _('The bluff was caught. %{player} takes %{cards}.')
      add_history(history, key, recipient, :move, message % {player: participant_name(recipient), cards: card_count_text(count, received: true)})
      state[:hands].fetch(recipient).concat(state[:pile])
      state[:pile].clear
      state[:reaction_order] = []
      variant = state[:options]['variant']
      if %w[fixed_bluff suit].include?(variant)
        # Cyclic profiles keep the claim; these profiles instead choose a new opener.
        state[:passed].clear
        state[:last_claim] = nil
        state[:last_packet] = nil
        opener = variant == 'suit' ? recipient : (truth ? packet[:actor] : actor)
        finish_or_advance(state, packet[:actor], key, history, next_player: opener)
      else
        finish_or_advance(state, packet[:actor], key, history)
      end
    end

    def finish_or_advance(state, author, key, history, next_player: nil)
      # Concealed plays reach this point only after reactions settle.
      if state[:hands].fetch(author).empty?
        state.update(winner: author, current_player: nil, phase: :finished)
        history << result_history(event_id: key, winner: author)
      else
        state.update(phase: :playing, current_player: next_player || next_unpassed(state, author))
      end
    end

    def next_unpassed(state, actor)
      index = state[:players].index(actor)
      (1..state[:players].length).each do |offset|
        candidate = state[:players][(index + offset) % state[:players].length]
        return candidate unless state[:passed].include?(candidate)
      end
      nil
    end

    def matches_claim?(card, claim, variant)
      card[variant == 'suit' ? 1 : 0] == claim
    end

    def add_history(history, key, actor, kind, text)
      history << HistoryEntry.new(key: "cheat:#{key}:#{history.length}", text: text,
        event_id: key, actor: actor, kind: kind)
    end

    def card_count_text(count, received: false)
      message = received ? np_('Cheat received cards', '%{count} card', '%{count} cards', count) :
        n_('%{count} card', '%{count} cards', count)
      message % {count: count}
    end

    def declaration_text(claim, count, variant)
      if variant == 'suit'
        return np_('Cheat declaration', '%{count} card; suit: %{suit}', '%{count} cards; suit: %{suit}', count) % {count: count, suit: suit_label(claim)}
      end
      message = case claim
      when 'A' then np_('Cheat declaration', '%{count} ace', '%{count} aces', count)
      when '2' then np_('Cheat declaration', '%{count} two', '%{count} twos', count)
      when '3' then np_('Cheat declaration', '%{count} three', '%{count} threes', count)
      when '4' then np_('Cheat declaration', '%{count} four', '%{count} fours', count)
      when '5' then np_('Cheat declaration', '%{count} five', '%{count} fives', count)
      when '6' then np_('Cheat declaration', '%{count} six', '%{count} sixes', count)
      when '7' then np_('Cheat declaration', '%{count} seven', '%{count} sevens', count)
      when '8' then np_('Cheat declaration', '%{count} eight', '%{count} eights', count)
      when '9' then np_('Cheat declaration', '%{count} nine', '%{count} nines', count)
      when 'T' then np_('Cheat declaration', '%{count} ten', '%{count} tens', count)
      when 'J' then np_('Cheat declaration', '%{count} jack', '%{count} jacks', count)
      when 'Q' then np_('Cheat declaration', '%{count} queen', '%{count} queens', count)
      when 'K' then np_('Cheat declaration', '%{count} king', '%{count} kings', count)
      end
      message % {count: count}
    end

    def rank_label(rank)
      {'A' => _('ace'), 'J' => _('jack'), 'Q' => _('queen'), 'K' => _('king'), 'T' => _('10')}.fetch(rank, rank)
    end

    def suit_label(suit)
      {'C' => _('clubs'), 'D' => _('diamonds'), 'H' => _('hearts'), 'S' => _('spades')}.fetch(suit, suit)
    end
  end
end

require_relative 'cheat/bot'
require_relative 'cheat/presentation'
require_relative 'generated/rulebooks/cheat'
