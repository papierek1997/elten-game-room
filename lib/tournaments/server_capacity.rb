require_relative 'league_plan'
require_relative 'group_plan'

module GameRoomTournaments
  # Validate the advertised capacity before anybody registers, using the same
  # pure planners as the real schedule. Never truncate an accepted tournament.
  module ServerCapacity
    MAX_MATCHES = 256
    module_function

    # Public registration assembles pairs. The separate local planner can
    # support larger fixed teams; generic game capabilities stay unchanged.
    def supported_player_counts(game:, options:)
      game.tournament_capabilities(options: options).fetch(:player_counts).select do |count|
        [0, 2].include?(game.team_size(options, player_count: count))
      end.freeze
    end

    def validate_match_size!(registry:, game_id:, settings:)
      game = registry.build(game_id)
      unless game && supported_player_counts(game: game, options: settings.fetch('game_options')).include?(settings.fetch('players_per_match'))
        raise Publication::Invalid, :invalid_players_per_match
      end
      true
    end

    def validate!(registry:, game_id:, settings:)
      validate_match_size!(registry: registry, game_id: game_id, settings: settings)
      people = settings.fetch('participant_limit', 128)
      seats = settings.fetch('players_per_match')
      team = registry.build(game_id).team_size(settings.fetch('game_options'), player_count: seats) == 2
      units = team ? people / 2 : people
      per_match = team ? seats / 2 : seats
      raise Publication::Invalid, :invalid_participant_limit if units < per_match
      participants = Array.new(units) { |index| "player-#{index}" }
      count = case settings.fetch('format')
      when 'round_robin'
        LeaguePlan.build(participants: participants, players_per_match: per_match,
          pairing: settings.fetch('pairing'), rematch: settings.fetch('rematch')).size
      when 'groups_knockout'
        group_settings = settings
        if Publication::ADVANCEMENT_SETTINGS.none? { |key| settings[key] }
          group_settings = settings.merge('group_advancement' => GroupAdvancement::AUTOMATIC)
        end
        # Match the real candidates: an automatic two-unit final is valid,
        # but three units must pass the real group planner, not a guessed
        # knockout count. A smaller actual roster need not be plannable just
        # because the advertised maximum was accepted at publication time.
        if units == 2 && GroupAdvancement.automatic?(group_settings['group_advancement'])
          1
        else
          GroupPlan.build(participants: participants, players_per_match: per_match,
            pairing: group_settings.fetch('pairing'), rematch: group_settings.fetch('rematch'),
            group_count: group_settings['group_count'], places_per_group: group_settings['places_per_group'],
            advancement: group_settings['group_advancement']).fetch('match_count')
        end
      when 'knockout' then units
      else raise Publication::Invalid, :unsupported_format
      end
      raise Publication::Invalid, :server_match_capacity if count > MAX_MATCHES
      true
    rescue LeaguePlan::Invalid => error
      raise Publication::Invalid, error.code.to_s.include?('too_many') ? :server_match_capacity : error.code
    end
  end
end
