module GameRoomGames
  using GameRoomLocalization::Translations

  class Cheat
    def event_presentation_stages(event, repository, _before, after, viewer)
      return nil unless event['action'] == 'challenge'
      id = repository.event_id(event)
      descriptions = describe_event(event, repository, after, viewer)
      (0..3).map do |index|
        {history: [HistoryEntry.new(key: "cue:#{id}:#{index}", kind: :cheat_challenge_stage, value: index)],
         descriptions: index == 3 ? descriptions : [], wait_for_sounds: true, defer_replay: index < 3}
      end
    end

    def surface_spec(replay, viewer)
      state = replay.state
      hand = hand_for(state, viewer).to_a
      cards = hand.map.with_index do |card, index|
        GameSurfaces::Card.new(id: card, value: card, label: playing_card_label(card),
          sort_keys: standard_hand_sort_keys(rank: card[0], suit: card[1], position: index),
          navigation_group: standard_hand_navigation_group(rank: card[0], suit: card[1]))
      end
      packet = GameSurfaces::PacketCardSpec.new(id: 'cheat_hand', header: _('Your hand'), cards: cards,
        action_name: 'play', allow_packet: state[:options]['variant'] != 'suit',
        hand_order: hand.dup, hand_epoch: [viewer.to_s.downcase, state[:seed]].join(':'),
        default_sort: default_hand_sort, sort_modes: hand_sort_modes,
        empty_label: _('Your hand is empty'), activation_tip: _('Press Enter to prepare a card play.'))
      commands = decision_commands(replay, viewer)
      return packet if commands.empty?
      GameSurfaces::CompositeSpec.new(parts: [
        GameSurfaces::SurfacePart.new(id: 'decision', surface: GameSurfaces::CommandPanelSpec.new(commands: commands)),
        GameSurfaces::SurfacePart.new(id: 'hand', surface: packet)])
    end

    def surface_action_shortcut(selection, replay, viewer)
      return nil unless selection['kind'] == 'card_packet' && selection['action'] == 'play'
      state = replay.state
      return nil unless state[:phase] == :playing && same_user?(state[:current_player], viewer)
      cards = JSON.parse(selection['cards'].to_s)
      return nil unless cards.is_a?(Array) && cards.all? { |card| hand_for(state, viewer).include?(card) }
      claims = allowed_claims(state)
      variant = state[:options]['variant']
      forced = claims.length == 1
      claim = claims.first
      prompt = if variant == 'suit' && state[:pile].empty?
        _('Open face up with %{card}?') % {card: playing_card_label(cards.first)}
      elsif forced
        _('Play %{declaration}?') % {declaration: declaration_text(claim, cards.length, variant)}
      end
      fields = forced ? [] : [OptionDefinition.new(key: 'choice', kind: :choice, label: _('Choose a declaration'),
        default: claim, choices: claims.map { |value| OptionChoice.new(value: value,
          label: _('Play %{declaration}?') % {declaration: declaration_text(value, cards.length, variant)}) })]
      GameShortcut.new(key: 'enter', label: _('Play cards'), kind: :form, prompt: prompt,
        action_kind: 'card_packet', action_name: 'play', submit_label: p_('Cheat submit', 'Play'), fields: fields,
        payload: {'cards' => selection['cards'], 'boundary' => state[:sequence].to_s(36), 'choice' => claim})
    rescue JSON::ParserError
      nil
    end

    def hand_sorting_available?(replay, viewer)
      !hand_for(replay.state, viewer).to_a.empty?
    end

    def playable_card_navigation(replay, viewer)
      return nil unless replay.state[:phase] == :playing && same_user?(replay.current_player, viewer)
      actions = legal_actions(replay, viewer).select { |action| action['action'] == 'play' && JSON.parse(action['cards']).length == 1 }
      grouped = actions.group_by { |action| JSON.parse(action['cards']).first }
      card_navigation_spec(hand_id: 'cheat_hand', card_actions: grouped, automatic_card_ids: [])
    end

    def shortcut_features; [:turn]; end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      result = [
        announcement_shortcut(key: 'c', label: _('read the public pile and declaration'), message: public_text(state)),
        announcement_shortcut(key: 's', label: _('read card counts'), message: counts_text(state)),
        announcement_shortcut(key: 'h', label: _('read your hand'), message: hand_text(state, viewer)),
        surface_shortcut(key: 'p', label: _('read the prepared packet'), command: 'announce_packet'),
        surface_shortcut(key: 'p', modifiers: [:shift], label: _('clear the prepared packet'), command: 'clear_packet')]
      result.find { |shortcut| shortcut.key == 'h' }.payload['hand_id'] = 'cheat_hand'
      decision_commands(replay, viewer).each do |command|
        key = {'challenge' => 'k', 'accept' => 'space', 'pass' => 'x'}.fetch(command.id)
        result << GameShortcut.new(key: key, label: command.label, kind: :action,
          action_kind: 'command', action_name: command.id, payload: command.payload)
      end
      result
    end

    private

    def decision_commands(replay, viewer)
      state = replay.state
      return [] if replay.finished? || !same_user?(replay.current_player, viewer)
      payload = {'boundary' => state[:sequence].to_s(36), 'packet' => state[:last_packet]&.fetch(:id)&.to_s(36)}
      choices = if state[:phase] == :reaction
        [['challenge', p_('Cheat decision', 'Challenge')], ['accept', _('Do not challenge')]]
      elsif state[:phase] == :playing && state[:options]['variant'] == 'fixed_bluff' && !state[:pile].empty?
        [['pass', _('Pass until the pile closes')]]
      else
        []
      end
      choices.map { |action, label| GameSurfaces::Command.new(id: action, label: label, enabled: true, payload: payload.dup) }
    end

    def counts_text(state)
      state[:players].map { |player| _('%{player}: %{cards}.') %
        {player: participant_full_name(player), cards: card_count_text(state[:hands].fetch(player).length)} }.join(' ')
    end

    def hand_text(state, viewer)
      hand = hand_for(state, viewer)
      return _('You are observing this game.') unless hand
      return _('Your hand is empty') if hand.empty?
      _('Your hand: %{cards}.') % {cards: hand_cards_for_display(hand).map { |card| playing_card_label(card) }.join('; ')}
    end

    def public_text(state)
      return _('Waiting for the deal.') if state[:phase] == :awaiting_deal
      message = _('Pile: %{cards}.') % {cards: card_count_text(state[:pile].length)}
      if state[:last_author] && state[:last_claim]
        message += ' ' + _('%{player} declared %{declaration}.') %
          {player: participant_name(state[:last_author]), declaration: declaration_text(state[:last_claim], state[:last_packet][:cards].length, state[:options]['variant'])}
      end
      if state[:phase] == :reaction
        message += ' ' + _('Reaction awaited from %{player}.') % {player: participant_name(state[:current_player])}
      elsif state[:phase] == :playing
        labels = allowed_claims(state).map { |claim| state[:options]['variant'] == 'suit' ? suit_label(claim) : rank_label(claim) }
        message += ' ' + (labels == [''] ? _('Open the pile with a face-up card.') : _('Available declarations: %{claims}.') % {claims: labels.join(', ')})
      end
      message
    end
  end
end
