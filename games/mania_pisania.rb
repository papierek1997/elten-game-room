# encoding: UTF-8
require_relative 'base'
require_relative '../lib/game_action_payload'
require_relative '../lib/mania_pisania/text_library'
require_relative '../lib/mania_pisania/shared_text'
require_relative '../lib/mania_pisania/text_selection'
require_relative '../lib/mania_pisania/scoring'
require_relative 'mania_pisania_support/saving'
require_relative '../lib/mania_pisania/rules'

module GameRoomGames
  using GameRoomLocalization::Translations

  # Starts, shared texts, checkpoints and final reports use LiveSessions. Input,
  # speech and timers belong to the local client and never block on a write.
  class ManiaPisania < Base
    include PublicHistoryAnnouncements
    include ManiaPisaniaSaving

    def id; 'mania_pisania'; end
    def name; _('Typoholism'); end
    def short_description; _('Practise typing, braille and memory alone or with friends.'); end
    def minimum_players; 1; end
    def maximum_players; 8; end
    def background_client?; true; end
    def shortcut_features; []; end
    def content_language_option_key; 'word_language'; end

    def table_creation_options(values = {})
      super.tap do |options|
        unless values.key?('word_language') || values.key?(:word_language)
          allowed = GameRoomTyping::Languages.visible
          options['word_language'] = allowed.first unless allowed.include?(options['word_language'])
        end
      end
    end

    def option_editor_definitions(selected = {})
      super.map do |definition|
        next definition unless %w[text word_language].include?(definition.key)
        copy = definition.dup
        copy.choices = definition.choices.select do |choice|
          if definition.key == 'word_language'
            GameRoomTyping::Languages.visible.include?(choice.value)
          else
            !GameRoomTyping::TextLibrary::BUILTIN.key?(choice.value) ||
              GameRoomTyping::Languages.visible.include?(GameRoomTyping::Languages.text_language(choice.value))
          end
        end
        copy
      end
    end

    # A new controller cannot inherit another person's unfinished local input.
    # Saving/restoring preserves the original seats through the shared archive.
    def controller_change_phase_error(replay)
      _('Wait until the current game has finished before changing its controller.') if replay.state[:phase] == :active
    end

    def option_definitions
      choice = ->(key, label, default, values, visible = nil) do
        OptionDefinition.new(key: key, label: label, kind: :choice, default: default,
          choices: values.map { |value, title| OptionChoice.new(value: value, label: title) }, visible_if: visible)
      end
      [choice.call('variant', _('Typing variant'), 'free', [
        ['free', _('Free typing')], ['words', _('Random words')], ['memory', _('Memory chain')], ['survival', _('Survival mode')]]),
        choice.call('word_language', _('Word language'), 'pl', [
          ['en', _('English')], ['pl', _('Polish')], ['cs', _('Czech')], ['es', _('Spanish')], ['ru', _('Russian')]],
          ->(options) { options['variant'] != 'free' && GameRoomTyping::Languages.visible.length > 1 }),
        choice.call('text', _('Text'), GameRoomTyping::TextLibrary.default_text, GameRoomTyping::TextLibrary::BUILTIN.map { |key, item| [key, item['title']] } +
          [['local', _('Choose a local text')], ['pasted', _('Paste a text')], ['own', _('Write your own text (solo only)')]], {'variant' => 'free'}),
        choice.call('minutes', _('Time limit'), 0, [[0, _('Until the text ends')], [1, _('1 minute')], [3, _('3 minutes')], [5, _('5 minutes')], [10, _('10 minutes')]], {'variant' => 'free'}),
        choice.call('input', _('Input method'), 'keyboard', [['keyboard', _('Keyboard')], ['braille', _('Braille typing')], ['mixed', _('Keyboard and braille, randomly mixed')]]),
        choice.call('difficulty', _('Survival difficulty'), 'easy', [['easy', _('Easy')], ['medium', _('Medium')], ['hard', _('Hard')]], {'variant' => 'survival'}),
        choice.call('rounds', _('Number of rounds'), 1, [[1, '1'], [3, '3'], [5, '5'], [10, '10'], [0, _('Until the host ends the match')]],
          ->(options) { options['variant'] != 'free' })]
    end

    def normalize_options(values)
      super.tap do |options|
        # All variants accept keyboard, braille or mixed input.
        options['rounds'] = 1 if options['variant'] == 'free'
        if options['variant'] == 'free'
          selection = GameRoomTyping::TextSelection.descriptor(values)
          if (builtin = GameRoomTyping::TextSelection::BUILTIN[options['text']])
            options.merge!(selection && selection['text_id'] == builtin['text_id'] ? selection : builtin)
          elsif %w[local pasted].include?(options['text']) && selection
            options.merge!(selection)
          end
        end
      end
    end

    def build_table_preparation(program)
      require_relative '../lib/mania_pisania/table_preparation'
      GameRoomTyping::TablePreparation.new(program, self)
    end

    def build_option_editor_extension(program, options)
      require_relative '../lib/mania_pisania/option_fields'
      GameRoomTyping::OptionFields.new(program, options)
    end

    def build_start_guard(program, user:, **_services)
      require_relative '../lib/mania_pisania/table_preparation'
      GameRoomTyping::TextStartGuard.new(program)
    end

    def notification_option_keys(_options); %w[variant word_language text text_title text_characters minutes]; end

    def notification_variant(options)
      parts = [notification_choice(options, 'variant')]
      parts << notification_choice(options, 'word_language') if options['variant'] != 'free'
      parts << notification_choice(options, 'minutes') if options['variant'] == 'free'
      if options['variant'] == 'free' && options['text_title'].is_a?(String) &&
          options['text_characters'].is_a?(Integer) && options['text_characters'].positive?
        parts << (GameRoomContent.utf8(_('Text: %{title}; character count: %{count}')) % {title: GameRoomContent.utf8(options['text_title']), count: options['text_characters']})
      end
      parts.compact.join('; ')
    end

    def options_summary(options); notification_variant(options); end

    def rules_options_text(options)
      text = super
      if options['variant'] == 'free' && options['text_title']
        text += "\r\n\r\n" + (GameRoomContent.utf8(_('Text: %{title}; character count: %{count}')) % {title: GameRoomContent.utf8(options['text_title']), count: options['text_characters']})
      end
      text
    end

    def build_client(program, **services)
      require_relative '../lib/mania_pisania/client'
      GameRoomTyping::Client.new(program, self, **services)
    end

    def personal_settings_label; _('Typing Mania settings'); end
    def personal_settings_action; :show_typing_settings; end

    def options_error(options, player_count: nil)
      if options['variant'] == 'free' && options['text'] == 'own' && player_count && player_count > 1
        _('Writing without a source text is available only when playing alone. Choose a shared text for multiplayer.')
      end
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = {options: options_from_json(session['options']), players: players,
        phase: :setup, round: 0, seed: nil, results: {}, rounds: [],
        scores: players.to_h { |player| [player, 0] }, owner: session['__table_owner'] || session['__insertion_user'] || players.first,
        winner: nil, draw: false}
      history, accepted = [starting_history(players)], []
      GameRoomActionPayload.each(events, id, repository, session) do |data, actor, batch|
        if %w[text_part save_begin save_cancel save_resume].include?(data['action'])
          next unless batch.all? { |event| same_user?(event['__insertion_user'] || actor, event['__authority_user'] || state[:owner]) }
        end
        next unless apply(state, data, actor)
        accepted.concat(batch)
        event_id = repository.event_id(batch.last)
        message = case data['action']
        when 'start'
          _('Round %{round}.') % {round: state[:round]}
        when 'result'
          result = data['result']
          text = _('%{player}: %{words} words, %{errors} errors, %{wpm} WPM.') % {
            player: participant_name(actor), words: result['words'], errors: result['errors'], wpm: result['wpm']}
          text += ' ' + scoring_text(result, state[:options]) if state[:scoring] == 1
          text
        when 'end'
          _('The host ended the match.')
        when 'text_part'
          _('Table text: %{title}.') % {title: state[:shared_text]['title']} if state[:shared_text]
        when 'save_begin' then _('Typing is paused while the game is being saved.')
        when 'save_cancel', 'save_resume' then _('Typing resumed.')
        end
        history << HistoryEntry.new(key: "typing:#{event_id}", event_id: event_id, actor: actor, kind: :move, text: message) if message
        if state[:phase] == :finished
          history << result_history(event_id: event_id, winner: state[:winner], draw: state[:draw])
        end
      end
      Replay.new(board: nil, players: players, current_player: nil, state: state,
        accepted_events: accepted, history: history, winner: state[:winner], draw: state[:draw])
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      action = selection['action'].to_s
      data = {'action' => action, 'round' => replay.state[:round]}
      if action == 'start'
        return [:invalid, nil] unless context&.random_source
        data['seed'] = context.random_source.roll(count: 4, sides: 256).values.reduce(0) { |seed, byte| (seed << 8) + byte - 1 }
        data['scoring'] = 1
      elsif action == 'result'
        return [:invalid, nil] unless selection['round'] == replay.state[:round]
        data['result'] = selection['result']
      elsif action == 'text_part'
        data['part'] = selection['part']
      elsif ManiaPisaniaSaving::SAVE_ACTIONS.include?(action)
        data['save_id'] = selection['save_id']
        data['checkpoint'] = selection['checkpoint'] if action == 'checkpoint'
      end
      candidate = Marshal.load(Marshal.dump(replay.state))
      return [:invalid, nil] unless apply(candidate, data, actor)
      [:ok, ActionPlan.new(events: GameRoomActionPayload.commands(id, data))]
    end

    def automatic_action(replay, actor, context: nil)
      local = context&.local_data || {}
      if (pending = local['typing_save_action'])
        # The worker can see an acknowledgement before the UI publishes its
        # next snapshot. Do not send that old request again, or in a new round.
        return nil unless pending['round'] == replay.state[:round] &&
          same_user?(pending['owner'], context.table_owner || replay.state[:owner])
        saving = replay.state[:saving]
        if pending['action'] == 'save_begin'
          return nil unless replay.state[:phase] == :active && !saving && replay.state[:resume_id] != pending['save_id']
        else
          return nil unless saving && saving[:id] == pending['save_id']
          return nil if pending['action'] == 'save_resume' && !save_ready?(replay)
        end
        return pending.merge('kind' => 'command')
      end
      if replay.state[:saving]
        checkpoint = local['typing_checkpoint']
        return nil unless checkpoint && !replay.state[:saving][:checkpoints].keys.any? { |name| same_user?(name, actor) }
        return {'kind' => 'typing', 'action' => 'checkpoint', 'save_id' => replay.state[:saving][:id], 'checkpoint' => checkpoint}
      end
      if replay.state[:phase] == :setup && shared_text_required?(replay.state) && !replay.state[:shared_text]
        parts = context&.local_data&.[]('typing_text_parts')
        return nil unless parts.is_a?(Array) && !parts.empty?
        transfer = replay.state[:text_transfer]
        matching = transfer && transfer.values_at(:digest, :title, :total) == parts.first.values_at('digest', 'title', 'total')
        index = matching ? transfer[:chunks].length : 0
        part = parts[index]
        return part && {'kind' => 'command', 'action' => 'text_part', 'part' => part}
      end
      pending = context&.local_data&.[]('typing_result')
      if pending && pending['round'] == replay.state[:round] && replay.state[:phase] == :active &&
          replay.players.any? { |name| same_user?(name, actor) } &&
          replay.state[:results].keys.none? { |name| same_user?(name, actor) }
        return {'kind' => 'typing', 'action' => 'result', 'round' => pending['round'], 'result' => pending['result']}
      end
      {'kind' => 'command', 'action' => 'start'} if replay.state[:phase] == :setup && same_user?(actor, replay.players.first)
    end

    def automatic_actor(replay, viewer, table_owner:)
      replay.state[:phase] == :setup ? super : viewer
    end

    def automatic_action_allowed?(replay, actor, table_owner:)
      same_user?(actor, table_owner) || (replay.state[:phase] == :active && replay.players.any? { |name| same_user?(name, actor) })
    end

    def automatic_action_due?(replay, actor, context: nil)
      automatic_action(replay, actor, context: context) != nil
    end

    def moderator_action?(selection)
      selection['kind'] == 'command' && %w[start end text_part save_begin save_cancel save_resume].include?(selection['action'])
    end

    def concurrent_session_input?(before, after, selection)
      selection['kind'] == 'typing' && selection['action'] == 'result' &&
        before.state[:phase] == :active && after.state[:phase] == :active &&
        before.state[:round] == after.state[:round] && before.state[:seed] == after.state[:seed]
    end

    def surface_spec(replay, viewer)
      state = replay.state
      playing = state[:phase] == :active && !state[:saving] && replay.players.any? { |name| same_user?(name, viewer) } &&
        state[:results].keys.none? { |name| same_user?(name, viewer) }
      commands = []
      if state[:saving] && same_user?(viewer, state[:owner])
        commands << GameSurfaces::Command.new(id: 'save_cancel', label: _('Resume typing without saving'), payload: {'save_id' => state[:saving][:id]})
      end
      if state[:phase] == :between && same_user?(viewer, state[:owner])
        commands << GameSurfaces::Command.new(id: 'start', label: _('Next round'))
        commands << GameSurfaces::Command.new(id: 'end', label: _('End match'))
      end
      status = replay.finished? ? result_text(replay) : _('Waiting for the other players or the next round.')
      choosing = state[:phase] == :setup && shared_text_required?(state) && !state[:shared_text]
      status = _('Waiting for the host to share the table text.') if choosing
      status = _('Waiting for all players to confirm their progress for the save.') if state[:saving]
      GameSurfaces::TypingSpec.new(round: state[:round], enabled: playing, status: status, commands: commands,
        remaining_sentence: sentence_help?(state[:options]), remaining_word: state[:options] && state[:options]['variant'] != 'memory' && !(state[:options]['variant'] == 'free' && state[:options]['text'] == 'own'),
        auto_commit: state[:options] && state[:options]['variant'] == 'survival', choose_text: choosing && same_user?(viewer, state[:owner]))
    end

    def custom_game_shortcuts(replay, viewer)
      return [] if replay.state[:saving]
      return [] unless replay.state[:phase] == :active && replay.players.any? { |name| same_user?(name, viewer) }
      shortcuts = [surface_shortcut(key: 'l', modifiers: [:control], label: _('spell the current word'), command: 'typing_spell'),
        surface_shortcut(key: 'o', modifiers: [:control], label: _('read the current word'), command: 'typing_repeat'),
        surface_shortcut(key: 's', modifiers: [:alt], label: _('read typing progress'), command: 'typing_status')]
      unless replay.state[:options] && (replay.state[:options]['variant'] == 'memory' || (replay.state[:options]['variant'] == 'free' && replay.state[:options]['text'] == 'own'))
        shortcuts << surface_shortcut(key: 'semicolon', modifiers: [:control], label: _('read the rest of the word'), command: 'typing_word_rest')
      end
      if sentence_help?(replay.state[:options])
        shortcuts << surface_shortcut(key: 'semicolon', modifiers: [:control, :shift], label: _('read the rest of the sentence'), command: 'typing_sentence')
      end
      shortcuts
    end

    def result_sound_cue(**_context); nil; end

    def participant_scores(replay); replay.state[:scores]; end
    def tournament_scores(replay, options:); participant_scores(replay); end
    def result_text(replay)
      return nil unless replay.finished?
      return super unless replay.players.length == 1
      result = replay.state[:results].values.first
      return _('Typing finished.') unless result
      text = _('%{words} words, %{errors} errors, %{wpm} WPM.') % {words: result['words'], errors: result['errors'], wpm: result['wpm']}
      text += ' ' + scoring_text(result, replay.state[:options]) if replay.state[:scoring] == 1
      text
    end
    def participant_status(replay, participant, connected: true)
      return _('disconnected') unless connected
      replay.state[:results].keys.any? { |name| same_user?(name, participant) } ? _('finished typing') : _('typing')
    end

    def rule_sections
      generated_rule_sections
    end

    def rule_book(options: nil)
      book = GameRoomTyping::RuleBook.new(game_id: id, title: name,
        sections: localized_rule_sections || rule_sections)
      options ? book.with_current_options(rules_options_text(normalize_options(options))) : book
    end

    private

    def scoring_text(result, options)
      _('Score: %{score}; accuracy factor: %{accuracy} percent.') % GameRoomTyping::Scoring.summary(result, options['variant'])
    end

    def shared_text_required?(state)
      GameRoomTyping::SharedText.required?(state[:options], state[:players], owner: state[:owner])
    end

    def sentence_help?(options)
      options && options['variant'] == 'free' && options['text'] != 'own'
    end

    def apply(state, data, actor)
      return false if state[:phase] == :finished || data['round'] != state[:round]
      return apply_save_action(state, data, actor) if ManiaPisaniaSaving::SAVE_ACTIONS.include?(data['action'])
      return false if state[:saving]
      case data['action']
      when 'start'
        return false unless [:setup, :between].include?(state[:phase]) && same_user?(actor, state[:players].first)
        return false if shared_text_required?(state) && !state[:shared_text]
        return false unless data['seed'].is_a?(Integer) && data['seed'].between?(0, 2**32 - 1)
        return false unless [nil, 1].include?(data['scoring'])
        state[:round] += 1
        state[:scoring] = data['scoring']
        state[:seed], state[:phase], state[:results] = data['seed'], :active, {}
      when 'text_part'
        return false unless state[:phase] == :setup && shared_text_required?(state) && !state[:shared_text] && same_user?(actor, state[:players].first)
        return false unless GameRoomTyping::SharedText.apply(state, data['part'])
      when 'result'
        player = state[:players].find { |name| same_user?(name, actor) }
        return false unless state[:phase] == :active && player && !state[:results].key?(player)
        return false unless valid_result?(data['result'])
        state[:results][player] = data['result'].dup
        finish_round(state) if state[:results].length == state[:players].length
      when 'end'
        return false unless state[:phase] == :between && same_user?(actor, state[:players].first)
        finish_match(state)
      else
        return false
      end
      true
    end

    def valid_result?(result)
      return false unless result.is_a?(Hash)
      %w[words errors levels elapsed_ms].all? { |key| result[key].is_a?(Integer) && result[key].between?(0, 1_000_000_000) } &&
        result['wpm'].is_a?(Numeric) && result['wpm'].finite? && result['wpm'].between?(0, 100_000) &&
        [true, false].include?(result['assisted'])
    end

    def finish_round(state)
      field = case state[:options]['variant']
      when 'free' then 'wpm'
      when 'survival' then 'words'
      else 'elapsed_ms'
      end
      eligible = state[:results].reject { |_name, result| result['assisted'] }
      values = eligible.transform_values do |result|
        state[:scoring] == 1 ? GameRoomTyping::Scoring.value(result, state[:options]['variant']) : result[field]
      end
      best = values.values.max
      winners = values.keys.select { |name| values[name] == best }
      winners.each { |name| state[:scores][name] += 1 }
      state[:rounds] << {results: state[:results].transform_values(&:dup), winners: winners}
      target = state[:options]['rounds'].to_i
      if target > 0 && state[:round] >= target
        finish_match(state)
      else
        state[:phase] = :between
      end
    end

    def finish_match(state)
      best = state[:scores].values.max
      winners = state[:players].select { |name| state[:scores][name] == best }
      state[:winner] = winners.first if winners.length == 1
      state[:draw] = winners.length != 1
      state[:phase] = :finished
    end
  end
end

require_relative 'generated/rulebooks/mania_pisania'
