require 'digest'
require_relative 'schema'
require_relative '../difficulty'
require_relative '../../game_participants'
require_relative '../../game_statistics_periods'
require_relative '../../game_statistics_store'

module GameRoomDartsRankings
  class InvalidResult < ArgumentError; end
  class Unavailable < GameRoomStatistics::Unavailable; end

  module Result
    DIFFICULTIES = (GameRoomDarts::Difficulty::IDS + ['progressive']).freeze
    FIELDS = %w[result_key difficulty played_at day_key rounds throw_count total_score total_time_ms
      best_round_score best_round_time_ms].freeze
    module_function

    def from_replay(session:, replay:, viewer:)
      return unless session.is_a?(Hash) && replay&.finished? && !session['__aborted']
      options = replay.state[:options]
      return unless options.is_a?(Hash) && options['mode'] == 'game'
      player = replay.players.find { |name| GameRoomParticipants.same?(name, viewer) }
      return unless player && !GameRoomParticipants.bot?(player) && !bot_controller?(session, player)
      identity = session.dig('__statistics', 'id')
      return unless identity.is_a?(String) && !identity.empty?
      terminal = replay.accepted_events.to_a.reverse.find { |event| event['action'].to_s == 'darts_throw' }
      played_at = terminal && terminal['created_at']
      return unless played_at.is_a?(Integer) && played_at.positive?

      throws = replay.state.fetch(:throws).fetch(player).reject { |item| item[:tiebreak] }
      rounds = options['rounds'].to_i
      return unless rounds.positive? && throws.length == rounds * 3
      # A final human occupant can inherit a bot's earlier throws through the
      # shared seat replay. Only the account's own accepted darts may count.
      regular_events = replay.accepted_events.select { |event| event['action'] == 'darts_throw' }.first(replay.players.length * rounds * 3)
      own_events = regular_events.count do |event|
        GameRoomParticipants.same?(event['actor'], player) && event['__controller'] != true
      end
      return unless own_events >= throws.length
      grouped = throws.group_by { |item| item.fetch(:round) }
      return unless grouped.length == rounds && grouped.values.all? { |items| items.length == 3 }
      triples = grouped.values.map do |items|
        [items.sum { |item| item.fetch(:points) }, items.sum { |item| item.fetch(:time_ms) }]
      end
      best_score, best_time = triples.min_by { |score, time| [-score, time] }
      difficulty = options['progressive'] ? 'progressive' : options['difficulty'].to_s
      row = {
        'result_key'=>Digest::SHA256.hexdigest("darts\0#{identity}\0#{player.downcase}"),
        'difficulty'=>difficulty, 'played_at'=>played_at, 'day_key'=>day(played_at), 'rounds'=>rounds,
        'throw_count'=>throws.length, 'total_score'=>throws.sum { |item| item.fetch(:points) },
        'total_time_ms'=>throws.sum { |item| item.fetch(:time_ms) },
        'best_round_score'=>best_score, 'best_round_time_ms'=>best_time
      }
      parse(row)
      row.to_h { |key, value| [key.freeze, value.is_a?(String) ? value.dup.freeze : value] }.freeze
    rescue KeyError, TypeError
      nil
    end

    def parse(row)
      unless row.is_a?(Hash) && row['result_key'].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(row['result_key']) &&
          DIFFICULTIES.include?(row['difficulty']) && valid_epoch?(row['played_at']) && row['day_key'] == day(row['played_at']) &&
          row['rounds'].is_a?(Integer) && row['rounds'].between?(1, 100) &&
          row['throw_count'] == row['rounds'] * 3 && row['throw_count'].between?(3, 300) &&
          integer_between?(row['total_score'], 0, row['throw_count'] * 100) &&
          integer_between?(row['total_time_ms'], 0, row['throw_count'] * 600_000) &&
          integer_between?(row['best_round_score'], 0, 300) && integer_between?(row['best_round_time_ms'], 0, 1_800_000) &&
          row['best_round_score'] <= row['total_score'] && row['best_round_time_ms'] <= row['total_time_ms'] &&
          row['total_score'] <= row['best_round_score'] * row['rounds'] &&
          (row['rounds'] != 1 || row['best_round_time_ms'] == row['total_time_ms'])
        raise InvalidResult, 'Invalid Darts ranking result'
      end
      row
    end

    def day(epoch)
      GameRoomStatistics::Periods.today(clock: -> { Time.at(epoch) }).strftime('%Y%m%d').to_i
    end

    def bot_controller?(session, player)
      session.fetch('__controllers', {}).any? do |name, controller|
        controller == 'bot' && GameRoomParticipants.same?(name, player)
      end
    end

    def valid_epoch?(value); value.is_a?(Integer) && value.between?(1, 253_402_214_399); end
    def integer_between?(value, first, last); value.is_a?(Integer) && value.between?(first, last); end
  end
end
