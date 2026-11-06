# encoding: UTF-8
require_relative '../../lib/mania_pisania/checkpoint'
require_relative '../../lib/mania_pisania/text_library'
require_relative '../../lib/mania_pisania/word_bank'

module GameRoomGames
  module ManiaPisaniaSaving
    using GameRoomLocalization::Translations
    SAVE_ACTIONS = %w[save_begin checkpoint save_cancel save_resume].freeze

    def supports_saved_games?; true; end

    def save_ready?(replay)
      saving = replay.state[:saving]
      saving && replay.players.all? { |player| replay.state[:results].key?(player) ||
        replay.players.length == 1 || saving[:checkpoints].key?(player) }
    end

    def save_game_error(replay)
      return super if replay.finished?
      replay.state[:saving]&.fetch(:checkpoints, {})&.each_value do |checkpoint|
        GameRoomTyping::Checkpoint.validate_word_source!(checkpoint, word_bank: GameRoomTyping::WordBank.for_options(replay.state[:options]))
      end
      return nil if replay.state[:phase] == :between || save_ready?(replay)
      _('Pause typing and wait for every player to confirm their progress before saving.')
    rescue ArgumentError
      _('The saved typing progress is not compatible with this word bank.')
    end

    def saved_game_requires_private_data?; true; end

    def saved_private_data(replay, context:)
      return nil unless replay.players.length == 1 && replay.state[:phase] == :active
      envelope = context.hidden_submissions.reveal(session_id: context.session_id,
        round_id: "mania-save:#{replay.state[:round]}", user: replay.players.first)
      raise ArgumentError, 'The private typing checkpoint is missing.' unless envelope
      validate_saved_private_data(replay, envelope.payload)
      envelope.payload
    end

    def validate_saved_private_data(replay, data)
      if replay.players.length != 1 || replay.state[:phase] != :active
        raise ArgumentError, 'Unexpected typing private data' unless data == nil
        return
      end
      unless data.is_a?(Hash) && data['format'] == 1 &&
          GameRoomTyping::Checkpoint.valid?(data['checkpoint'], variant: replay.state[:options]['variant'], seed: replay.state[:seed])
        raise ArgumentError, 'Invalid private typing checkpoint'
      end
      source = data['source']
      if source
        raise ArgumentError, 'Invalid saved typing text' unless source.is_a?(Hash) && source['title'].is_a?(String) &&
          source['title'].length <= 150 && source['text'].is_a?(String) && source['text'].bytesize <= GameRoomTyping::TextLibrary::MAX_BYTES
        document = GameRoomTyping::Document.new(source['text'])
        if replay.state[:options]['variant'] == 'free' && data['checkpoint']['engine']['position'] > document.tokens.length
          raise ArgumentError, 'Invalid saved typing position'
        end
      end
      if replay.state[:options]['variant'] == 'free' && replay.state[:options]['text'] != 'own' && !source
        raise ArgumentError, 'The saved text is missing'
      end
      GameRoomTyping::Checkpoint.validate_word_source!(data['checkpoint'], word_bank: GameRoomTyping::WordBank.for_options(replay.state[:options]))
    end

    def restore_private_data(replay, data, context:)
      validate_saved_private_data(replay, data)
      return unless data
      context.hidden_submissions.prepare(session_id: context.session_id, round_id: "mania-save:#{replay.state[:round]}",
        user: replay.players.first, payload: data)
    end

    private

    def apply_save_action(state, data, actor)
      case data['action']
      when 'save_begin'
        return false unless state[:phase] == :active && !state[:saving] && same_user?(actor, state[:players].first)
        return false unless data['save_id'].is_a?(String) && data['save_id'].match?(/\A[0-9a-f]{32}\z/)
        state[:saving] = {id: data['save_id'], checkpoints: {}}
      when 'checkpoint'
        saving = state[:saving]
        player = state[:players].find { |name| same_user?(name, actor) }
        return false unless saving && saving[:id] == data['save_id'] && player && state[:players].length > 1 && !saving[:checkpoints].key?(player)
        return false unless GameRoomTyping::Checkpoint.valid?(data['checkpoint'], variant: state[:options]['variant'], seed: state[:seed])
        state[:saving] = saving.merge(checkpoints: saving[:checkpoints].merge(player => data['checkpoint']))
      when 'save_cancel', 'save_resume'
        saving = state[:saving]
        return false unless saving && saving[:id] == data['save_id'] && same_user?(actor, state[:players].first)
        if data['action'] == 'save_resume'
          return false unless state[:players].all? { |player| state[:players].length == 1 || state[:results].key?(player) || saving[:checkpoints].key?(player) }
        end
        state[:resume_checkpoints] = saving[:checkpoints]
        state[:resume_id] = saving[:id]
        state[:saving] = nil
      else
        return false
      end
      true
    end
  end
end
