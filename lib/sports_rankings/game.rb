require_relative 'result'

module GameRoomSportsRankings
  # Opt-in to personal statistics, using the game's existing
  # public score and team contracts rather than a second scoring model.
  module Game
    def supports_player_statistics?; true; end

    def build_player_statistics_client(program)
      require_relative 'screen'
      Screen.new(program: program, game: self, service: program.class.sports_rankings_service,
        unavailable: -> { program.server_feature_unavailable_message(:statistics) })
    end

    def sports_ranking_result(replay)
      return unless replay.finished? && !replay.draw
      options = replay.state.fetch(:options)
      # Ordinary-game replacements preserve seat/team membership but not the
      # original confirmation names. Export the model's current assignment;
      # do not change the stored options or tournament admission rules.
      assignment = team_assignment(options, players: replay.players)
      if assignment&.valid?
        options = with_team_assignment(options, players: replay.players, seats: assignment.seats)
      end
      outcome = tournament_result(replay, options: options)
      return unless outcome[:units].size == 2 && outcome[:winners].size == 1
      goals = tournament_export_small_scores(replay, options: options).fetch(:scores)
      units = outcome[:units].keys
      sides = units.map do |unit|
        members = outcome[:units].fetch(unit)
        values = goals.key?(unit) ? [goals.fetch(unit)] : members.map { |member| goals.fetch(member) }
        raise InvalidResult, 'Team goal totals disagree' unless values.uniq.size == 1
        {seats: members.map { |member| replay.players.index(member) }, goals: values.first}
      end
      {sides: sides, winner: units.index(outcome[:winners].first)}
    end
  end
end
