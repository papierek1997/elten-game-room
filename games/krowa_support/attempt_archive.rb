# encoding: UTF-8
require_relative 'attempt_history'

module GameRoomGames
  # Optional immutable details. Scores reference a history only after every
  # part has been read back. This is not a second game/event backend.
  class KrowaAttemptArchive
    TABLE = 'krowa_attempt_lists'.freeze
    PART_BYTES = 2048
    MAX_PARTS = KrowaAttemptHistory::MAX_BYTES / PART_BYTES

    def initialize(tables, user:)
      @tables, @user = tables, user.to_s
    end

    def publish(scope, values)
      list = KrowaAttemptHistory.words(values)
      key = KrowaAttemptHistory.identity(scope, list)
      existing = read(key, @user)
      nonce = existing.first&.fetch('nonce')
      payload, nonce = KrowaAttemptHistory.encode(scope, list, nonce: nonce)
      parts = payload.scan(/.{1,2048}/).each_with_index.map do |part, index|
        {'list_key' => key, 'part' => index, 'parts' => (payload.bytesize + PART_BYTES - 1) / PART_BYTES,
          'nonce' => nonce, 'payload' => part}
      end
      raise ArgumentError, 'Too many history parts' if parts.length > MAX_PARTS
      existing.each do |row|
        expected = parts[row['part']]
        raise ArgumentError, 'Conflicting history part' unless expected && expected.all? { |field, value| row[field] == value }
      end
      present = existing.to_h { |row| [row['part'], true] }
      missing = parts.reject { |part| present[part['part']] }
      missing.each_slice(100) do |batch|
        begin
          table.insert_many(batch)
        rescue StandardError => error
          raise unless error.is_a?(IOError) || (defined?(EltenLink::Error) && error.is_a?(EltenLink::Error))
          # Reconcile only this write. Never repeat the uncertain batch.
          return nil unless fetch(scope, key, user: @user) == list
          return key
        end
      end
      fetch(scope, key, user: @user) == list ? key : nil
    end

    def fetch(scope, key, user:)
      return nil if key.to_s.empty?
      raise ArgumentError, 'Invalid history key' unless /\A[0-9a-f]{64}\z/.match?(key)
      rows = read(key, user)
      return nil if rows.empty?
      total = rows.first['parts']
      raise ArgumentError, 'Invalid history part count' unless total.is_a?(Integer) && total.between?(1, MAX_PARTS)
      return nil unless rows.length == total && rows.map { |row| row['part'] } == (0...total).to_a
      nonce = rows.first['nonce']
      raise ArgumentError, 'Conflicting history metadata' unless rows.all? { |row| row['parts'] == total && row['nonce'] == nonce }
      KrowaAttemptHistory.decode(scope, key, rows.map { |row| row['payload'] }.join, nonce)
    end

    private

    def table; @table ||= @tables.fetch(TABLE); end

    def read(key, user)
      rows, offset, canonical_nonce = {}, 0, nil
      loop do
        page = table.select(where: {'list_key' => key, '__insertion_user' => user},
          order: [['__id', 'asc']], limit: 500, offset: offset).to_a
        break if page.empty?
        page.each do |row|
          raise ArgumentError, 'Unexpected history author or key' unless row['list_key'] == key &&
            row['__insertion_user'].to_s.casecmp(user.to_s).zero?
          index = row['part']
          raise ArgumentError, 'Invalid history part' unless index.is_a?(Integer) && index.between?(0, MAX_PARTS - 1) &&
            row['payload'].is_a?(String) && row['payload'].bytesize.between?(1, PART_BYTES) &&
            row['nonce'].is_a?(String) && /\A[A-Za-z0-9+\/]{16}\z/.match?(row['nonce'])
          # Concurrent identical publications can choose different nonces.
          # The first native row fixes the envelope; never combine its parts
          # with a competing copy. A retry can complete that original copy.
          canonical_nonce ||= row['nonce']
          next unless row['nonce'] == canonical_nonce
          if rows[index] && %w[parts nonce payload].any? { |field| rows[index][field] != row[field] }
            raise ArgumentError, 'Conflicting duplicate history part'
          end
          rows[index] ||= row
        end
        offset += page.length
        raise ArgumentError, 'Too many duplicate history parts' if offset > MAX_PARTS * 4
      end
      rows.sort.map(&:last)
    end
  end
end
