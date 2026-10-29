require_relative '../game_participants'

module GameRoomSportsRankings
  # A player's own match counts and head-to-head counts against each
  # opponent (a pair in doubles), per period. Pure: no storage or networking.
  module Personal
    # In the order of the statistics screen's period choices.
    PERIODS = %w[all week month half_year year].freeze
    module_function

    # Inclusive first day of each period; half-year and year are calendar-month intervals.
    def first_days(today)
      {'week'=>today - 6, 'month'=>today - 29, 'half_year'=>(today << 6) + 1, 'year'=>(today << 12) + 1}.transform_values { |date| date.strftime('%Y%m%d').to_i }
        .merge('all'=>0)
    end

    # matches: [{'day_key'=>, 'sides'=>[{'players'=>, ...}, ...], 'winner'=>}]
    # Returns the player first, then opponents alphabetically.
    def summary(matches, user:, today:)
      firsts = first_days(today)
      blank = -> { PERIODS.to_h { |period| [period, {'won'=>0, 'lost'=>0}] } }
      own, opponents = {'players'=>[user], 'own'=>true, 'periods'=>blank.call}, {}
      matches.each do |match|
        sides = match.fetch('sides')
        side = sides.index { |entry| GameRoomParticipants.includes?(entry.fetch('players'), user) }
        next unless side
        other = sides.fetch(1 - side).fetch('players')
        opponent = opponents[other.map(&:downcase).sort] ||= {'players'=>other.sort_by(&:downcase), 'own'=>false, 'periods'=>blank.call}
        result = match.fetch('winner') == side ? 'won' : 'lost'
        PERIODS.each do |period|
          next if match.fetch('day_key') < firsts.fetch(period)
          [own, opponent].each { |entry| entry.fetch('periods').fetch(period)[result] += 1 }
        end
      end
      [own] + opponents.sort.map(&:last)
    end
  end
end
