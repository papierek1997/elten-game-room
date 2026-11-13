module GameRoomGames
  using GameRoomLocalization::Translations

  # A partial tie is a shared win, not a draw for the lower-scoring players.
  module ScoreSheetResults
    def score_sheet_winners(replay)
      return [] unless replay.finished?
      scores = participant_scores(replay)
      maximum = scores.values.max
      replay.players.select { |player| scores.fetch(player) == maximum }
    end

    def result_text(replay)
      winners = score_sheet_winners(replay)
      return super unless winners.length.between?(2, replay.players.length - 1)
      _("Winners: %{players}") % {players: winners.map { |player| participant_name(player) }.join(', ')}
    end

    def bot_reward(replay, actor)
      winners = score_sheet_winners(replay)
      return 0.0 if winners.empty? || winners.length == replay.players.length
      winners.any? { |player| same_user?(player, actor) } ? 1.0 : -1.0
    end

    def result_sound_cue(before_replay:, after_replay:, viewer:, default_cue:)
      return default_cue unless before_replay && !before_replay.finished? && after_replay&.finished?
      return nil unless GameRoomParticipants.includes?(after_replay.players, viewer)
      winners = score_sheet_winners(after_replay)
      return default_cue unless winners.length.between?(2, after_replay.players.length - 1)
      bot_reward(after_replay, viewer).positive? ? 'win_party' : 'lose_party'
    end
  end
end
