require_relative '../../lib/tournament_marker'

module GameRoomGames
  # Round games may remove a seat through the authenticated tournament boundary.
  # Models retain the original roster for result validation and historical actors.
  module RoundTournament
    using GameRoomLocalization::Translations

    def tournament_active_players(replay, options:)
      tournament_contenders(replay.state)
    end

    def tournament_forfeit_continuation(replay, losing_unit:, options:)
      active = tournament_active_players(replay, options: options)
      return {'status'=>'unsupported'} if replay.finished? || !GameRoomParticipants.includes?(active, losing_unit)
      {'status'=>active.size > 2 ? 'continue' : 'cannot_continue'}
    end

    def tournament_scored_checkpoint(replay, options:)
      replay.state[:tournament_checkpoint] || {'status'=>'none'}
    end

    def tournament_placement_result(replay, options:)
      result = super
      winners = replay.state[:winners]
      return result if !winners || winners.empty?
      result.merge(winners: winners.dup, draw: false)
    end

    def tournament_placement_scores(replay, options:)
      # Places, not small points. The tournament's small-point policy is separate.
      {scores: tournament_round_scores(replay.state), order: 'higher'}
    end

    private

    def enable_round_tournament(state, session)
      state[:round_tournament] = true if GameRoomTournamentMarker.present?(session)
    end

    def tournament_contenders(state)
      tournament_remaining_players(state) - tournament_inactive_players(state)
    end

    def tournament_inactive_players(state)
      state.fetch(:eliminated, [])
    end

    def apply_round_tournament_elimination(state, event, event_id, history)
      departed = tournament_elimination_players(event, players: state[:players])
      return false unless departed
      active = tournament_contenders(state)
      return false unless (departed - active).empty? && (active - departed).size >= 2

      (state[:tournament_eliminations] ||= []) << departed
      state[:round_tournament] = true
      departed.each_with_index do |player, index|
        history << HistoryEntry.new(key: "departure:#{event_id}:#{index}", event_id: event_id,
          actor: player, kind: :departure, text: _("%{player} left this game.") % {player: participant_name(player)})
      end
      yield departed
      true
    end

    def record_tournament_round(state, event_id, kind: 'round', index: state[:round])
      return unless state[:round_tournament]
      remember_tournament_checkpoint(state, event_id: event_id, index: index, kind: kind,
        scores: tournament_round_scores(state))
    end

    def record_tournament_winners(state, winners)
      state[:winners] = winners.dup if state[:round_tournament]
    end
  end
end
