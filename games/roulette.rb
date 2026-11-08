require_relative 'base'
require_relative '../lib/game_bots'
require_relative '../lib/roulette_bets'

module GameRoomGames
  using GameRoomLocalization::Translations

  class Roulette < Base
    include PublicHistoryAnnouncements
    GameRoomServerRandom.register('roulette', %w[spin])
    def id; 'roulette'; end
    def name; _('Roulette'); end
    def short_description; _('Place chips on numbers or groups and spin a European, American or French wheel.'); end
    def minimum_players; 1; end
    def maximum_players; 8; end
    def supports_bots?; true; end
    def bot_strategy; @bot_strategy ||= GameRoomBots::HeuristicStrategy.new; end
    def rule_sections; generated_rule_sections; end
    def notification_option_keys(_options); %w[mode wheel]; end

    def option_definitions
      [OptionDefinition.new(key: 'mode', label: _('Game mode'), kind: :choice, default: 'casino', choices: [
         OptionChoice.new(value: 'casino', label: _('Casino: automatic croupier and fixed payouts')),
         OptionChoice.new(value: 'social', label: _('Social: shared pool and rotating spinner'))]),
       OptionDefinition.new(key: 'wheel', label: _('Roulette wheel'), kind: :choice, default: 'european', choices: [
         OptionChoice.new(value: 'european', label: _('European: single zero')),
         OptionChoice.new(value: 'american', label: _('American: zero and double zero')),
         OptionChoice.new(value: 'french', label: _('French: single zero and la partage'))]),
       OptionDefinition.new(key: 'starting_chips', label: _('Starting chips (10-10000)'), kind: :integer, default: 1000),
       OptionDefinition.new(key: 'round_limit', label: _('Number of spins (1-100)'), kind: :integer, default: 10)]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _('Social roulette requires at least two players.') if values['mode'] == 'social' && player_count && player_count < 2
      return _('Choose from 10 to 10000 starting chips.') unless values['starting_chips'].is_a?(Integer) && values['starting_chips'].between?(10, 10_000)
      return _('Choose from 1 to 100 spins.') unless values['round_limit'].is_a?(Integer) && values['round_limit'].between?(1, 100)
      nil
    end

    def replay(session, events, repository)
      players, options = repository.players_for(session), options_from_json(session['options'])
      state = {players: players, options: options, chips: players.to_h { |p| [p, options['starting_chips'] * 2] },
        round: 1, phase: :betting, current_player: players.first, order: players.dup, spinner: players.first,
        bets: players.to_h { |p| [p, {}] }, ready: [], last_number: nil, winner: nil, draw: false}
      accepted, history, seen = [], [starting_history(players)], {}
      events.each do |event|
        break if state[:phase] == :finished
        event_id, actor = repository.event_id(event), repository.actor_of(event, session)
        next if seen[event_id] || !apply_roulette_event(state, event, actor, event_id, history)
        accepted << event
        seen[event_id] = true
      end
      Replay.new(board: nil, players: players, current_player: state[:current_player], winner: state[:winner],
        draw: state[:draw], state: state, history: history, accepted_events: accepted)
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || replay.state[:options]['mode'] != 'casino' || !same_user?(actor, replay.players.first)
      {'kind' => 'command', 'action' => 'spin'} if replay.state[:phase] == :spinning
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || !same_user?(replay.current_player, actor)
      state = replay.state
      return state[:options]['mode'] == 'social' ? [{'kind' => 'command', 'action' => 'spin'}] : [] if state[:phase] == :spinning
      amount = [10, state[:chips][state[:current_player]] / 2].min
      actions = amount > 0 ? bet_definitions(state).map { |bet| {'kind' => 'command', 'action' => 'bet', 'bet' => bet[:key], 'amount' => amount, 'round' => state[:round]} } : []
      actions << {'kind' => 'command', 'action' => 'clear', 'round' => state[:round]} unless state[:bets][state[:current_player]].empty?
      actions << {'kind' => 'command', 'action' => 'ready', 'round' => state[:round]}
      actions
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      state, action = replay.state, selection['action'].to_s
      if action == 'spin'
        expected = state[:options]['mode'] == 'casino' ? state[:players].first : state[:spinner]
        return [:not_your_turn, nil] unless same_user?(actor, expected)
        return [:invalid, nil] unless state[:phase] == :spinning && context&.random_source
        sides = state[:options]['wheel'] == 'american' ? 38 : 37
        return [:ok, ActionPlan.new(events: [GameRoomServerRandom.command(action: 'spin', count: 1, sides: sides)])] if context.server_random
        return [:ok, event_plan('spin', context.random_source.roll(count: 1, sides: sides).values.first.to_s)]
      end
      return [:not_your_turn, nil] unless same_user?(replay.current_player, actor)
      return [:invalid, nil] unless state[:phase] == :betting && selection['round'] == state[:round]
      player = state[:current_player]
      case action
      when 'bet'
        amount, key = selection['amount'], selection['bet']
        amount = amount.to_i if amount.is_a?(String) && /\A[1-9]\d{0,9}\z/.match?(amount)
        return [:invalid_bet, nil] unless amount.is_a?(Integer) && amount.between?(1, 1_000_000_000) && amount * 2 <= state[:chips][player] &&
          bet_definitions(state).any? { |bet| bet[:key] == key }
        return [:ok, event_plan('bet', "#{state[:round]}|#{key}|#{amount}")]
      when 'clear', 'ready'
        return [:ok, event_plan(action, state[:round].to_s)]
      end
      [:invalid, nil]
    end

    def surface_spec(replay, viewer)
      state = replay.state
      player = state[:players].find { |p| same_user?(p, viewer) }
      items = []
      if player && same_user?(replay.current_player, player) && !replay.finished?
        legal_actions(replay, viewer).each do |action|
          label = if action['action'] == 'bet'
            bet = bet_definitions(state).find { |b| b[:key] == action['bet'] }
            _('Bet %{amount} on %{bet}') % {amount: action['amount'], bet: bet_label(bet)}
          else
            {'ready' => _('Finish betting'), 'clear' => _('Remove all my bets'), 'spin' => _('Spin the wheel')}.fetch(action['action'])
          end
          items << GameSurfaces::PawnTrackItem.new(id: "#{action['action']}:#{action['bet']}", label: GameRoomContent.utf8(label), action: GameSurfaces::Action.from_h(action))
        end
      end
      header = _('Spin %{round}; last number %{number}; your chips %{chips}.') % {
        round: state[:round], number: state[:last_number].nil? ? '-' : GameRoomRouletteBets.display(state[:last_number]), chips: player ? state[:chips][player] / 2.0 : '-'}
      GameSurfaces::PawnTrackSpec.new(id: 'roulette', header: GameRoomContent.utf8(header), items: items,
        empty_label: GameRoomContent.utf8(current_turn_shortcut_text(replay, viewer)))
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      shortcuts = [announcement_shortcut(key: 's', label: _('read the chip balances'), message: state[:players].map { |p| "#{participant_name(p)}: #{state[:chips][p] / 2.0}" }.join('; '))]
      player = state[:players].find { |p| same_user?(p, viewer) }
      if player
        bets = state[:bets][player].map do |key, amount|
          bet = bet_definitions(state).find { |b| b[:key] == key }
          "#{bet_label(bet)}: #{amount / 2.0}"
        end
        shortcuts << announcement_shortcut(key: 'v', label: _('read your roulette bets'), message: bets.empty? ? _('You have no bets on this spin.') : bets.join('; '))
      end
      return shortcuts if replay.finished? || !same_user?(replay.current_player, viewer)
      if state[:phase] == :spinning && state[:options]['mode'] == 'social'
        shortcuts << GameShortcut.new(key: 'space', label: _('spin the wheel'), kind: :action, action_kind: 'command', action_name: 'spin', payload: {})
      elsif state[:phase] == :betting
        if state[:chips][player] >= 2
          fields = [OptionDefinition.new(key: 'bet', label: _('Roulette bet'), kind: :choice,
            default: 'red', choices: bet_definitions(state).map { |b| OptionChoice.new(value: b[:key], label: bet_label(b)) }),
            OptionDefinition.new(key: 'amount', label: _('Number of chips to bet'), kind: :integer, default: [10, state[:chips][player] / 2].min)]
          shortcuts << GameShortcut.new(key: 'b', label: _('place a bet with your own amount'), kind: :form,
            prompt: _('Place roulette bet'), fields: fields, action_kind: 'command', action_name: 'bet', payload: {'round' => state[:round]})
        end
        [['r', 'ready', _('finish betting')], ['c', 'clear', _('remove all your bets')]].each do |key, action, label|
          shortcuts << GameShortcut.new(key: key, label: label, kind: :action, action_kind: 'command', action_name: action, payload: {'round' => state[:round]})
        end
      end
      shortcuts
    end

    def participant_scores(replay); replay.state[:chips].transform_values { |amount| amount / 2.0 }; end
    def eliminated_from_game?(replay, viewer)
      player = replay.players.find { |p| same_user?(p, viewer) }
      player && replay.state[:chips][player] < 2 && replay.state[:bets][player].empty?
    end
    def bot_action_score(replay, actor, action, context: nil)
      return 100 if action['action'] == 'spin'
      return -100 if action['action'] == 'clear'
      return replay.state[:bets][replay.current_player].empty? ? -1 : 100 if action['action'] == 'ready'
      1
    end
    def move_error(status)
      return _('Choose a valid bet and a positive whole number of chips within your balance.') if status == :invalid_bet
      super
    end
    def event_sound_cues(event:, **_arguments)
      {'bet' => 'roulette_chips', 'spin' => 'roulette_spin'}[event['action']]
    end

    private

    def bet_definitions(state)
      @bet_definitions ||= {}
      @bet_definitions[state[:options]['wheel']] ||= GameRoomRouletteBets.definitions(state[:options]['wheel'])
    end

    def bet_label(bet)
      labels = {'red' => _('Red'), 'black' => _('Black'), 'odd' => _('Odd'), 'even' => _('Even'),
        'low' => _('Low: 1-18'), 'high' => _('High: 19-36'),
        'dozen1' => _('First dozen'), 'dozen2' => _('Second dozen'), 'dozen3' => _('Third dozen'),
        'column1' => _('First column'), 'column2' => _('Second column'), 'column3' => _('Third column')}
      GameRoomContent.utf8(_('%{bet}, pays %{odds} to 1')) % {bet: GameRoomContent.utf8(labels.fetch(bet[:label], bet[:label])), odds: bet[:odds]}
    end

    def apply_roulette_event(state, event, actor, event_id, history)
      action, value = event['action'].to_s, event['value'].to_s
      if action == 'spin'
        spinner = state[:options]['mode'] == 'casino' ? state[:players].first : state[:spinner]
        sides = state[:options]['wheel'] == 'american' ? 38 : 37
        return false unless state[:phase] == :spinning && same_user?(actor, spinner) && /\A[1-9]\d?\z/.match?(value) && value.to_i <= sides
        settle_spin(state, value.to_i - 1, event_id, history)
        return true
      end
      return false unless state[:phase] == :betting && same_user?(actor, state[:current_player])
      player = state[:current_player]
      if action == 'bet'
        match = /\A([1-9]\d{0,2})\|([a-z0-9]+)\|([1-9]\d{0,15})\z/.match(value)
        return false unless match && match[1].to_i == state[:round]
        key, amount = match[2], match[3].to_i * 2
        return false unless amount <= 2_000_000_000 && amount <= state[:chips][player] && bet_definitions(state).any? { |b| b[:key] == key }
        state[:chips][player] -= amount
        state[:bets][player][key] = state[:bets][player].fetch(key, 0) + amount
        label = bet_label(bet_definitions(state).find { |b| b[:key] == key })
        message = _('%{player} bets %{amount} on %{bet}.') % {player: participant_name(player), amount: amount / 2.0, bet: label}
      elsif action == 'clear' && value == state[:round].to_s
        state[:chips][player] += state[:bets][player].values.sum
        state[:bets][player] = {}
        message = _('%{player} removes their bets.') % {player: participant_name(player)}
      elsif action == 'ready' && value == state[:round].to_s
        state[:ready] << player
        state[:current_player] = (state[:order] - state[:ready]).first
        state[:phase], state[:current_player] = :spinning, state[:spinner] unless state[:current_player]
        message = _('%{player} finishes betting.') % {player: participant_name(player)}
      else
        return false
      end
      history << HistoryEntry.new(key: "roulette:#{event_id}", event_id: event_id, actor: actor, kind: :move, text: message)
      true
    end

    def settle_spin(state, number, event_id, history)
      payouts = state[:players].to_h do |player|
        winnings = state[:bets][player].sum do |key, amount|
          GameRoomRouletteBets.payout(bet_definitions(state).find { |b| b[:key] == key }, amount, number, state[:options]['wheel'])
        end
        [player, winnings]
      end
      if state[:options]['mode'] == 'social'
        pot, weight = state[:bets].values.sum { |bets| bets.values.sum }, payouts.values.sum
        if weight.zero?
          payouts = state[:bets].transform_values { |bets| bets.values.sum }
        else
          winning_players = state[:order].select { |p| payouts[p] > 0 }
          payouts.transform_values! { |win| pot * win / weight }
          remainder = pot - payouts.values.sum
          winning_players.cycle.take(remainder).each { |p| payouts[p] += 1 }
        end
      end
      payouts.each { |player, amount| state[:chips][player] += amount }
      state[:last_number] = number
      history << HistoryEntry.new(key: "roulette:#{event_id}", event_id: event_id, actor: state[:spinner], kind: :move,
        text: _('The ball lands on %{number}. Returns: %{returns}.') % {number: GameRoomRouletteBets.display(number), returns: payouts.map { |p, amount| "#{participant_name(p)}: #{amount / 2.0}" }.join('; ')})
      alive = state[:players].select { |p| state[:chips][p] >= 2 }
      if state[:round] >= state[:options]['round_limit'] || alive.empty? || (state[:options]['mode'] == 'social' && alive.size < 2)
        best = state[:chips].values.max
        winners = state[:players].select { |p| state[:chips][p] == best }
        state[:phase], state[:current_player], state[:winner], state[:draw] = :finished, nil, winners.size == 1 ? winners.first : nil, winners.size > 1
        state[:last_bets] = state[:bets]
        state[:bets] = state[:players].to_h { |p| [p, {}] }
        history << result_history(event_id: event_id, winner: state[:winner], draw: state[:draw])
      else
        state[:round] += 1
        offset = state[:options]['mode'] == 'social' ? state[:players].index(state[:spinner]) + 1 : (state[:round] - 1) % state[:players].size
        state[:order] = state[:players].rotate(offset) & alive
        state[:spinner] = state[:options]['mode'] == 'casino' ? state[:players].first : state[:order].first
        state[:current_player], state[:phase], state[:ready] = state[:order].first, :betting, []
        state[:bets] = state[:players].to_h { |p| [p, {}] }
      end
    end
  end
end

require_relative 'generated/rulebooks/roulette'
