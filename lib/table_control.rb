require "json"
require "digest"
require_relative "game_participants"

# A control record is not authoritative merely because it says "owner".
# Its digest must be anchored in the native session's owner-only discovery
# metadata. Stack authors are supplied by LiveSessions, never by the packet.
# This also permits a late joiner to verify historical controllers after the
# original owner has left, without granting that owner current permissions.
class GameRoomTableControl
  KIND = "table_control".freeze
  ANCHOR_KEY = "control_anchor".freeze
  MAX_SEATS = 9

  def self.canonical(value)
    case value
    when Hash
      value.keys.sort.each_with_object({}) { |key, copy| copy[key] = canonical(value[key]) }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end

  def self.anchor(record)
    { "seq" => record.sequence, "digest" => Digest::SHA256.hexdigest(JSON.generate(canonical(
      "sequence" => record.sequence, "sender" => record.sender, "packet" => record.packet))) }
  end

  def self.valid_anchor?(value)
    value.is_a?(Hash) && value.keys.sort == %w[digest seq] &&
      value["seq"].is_a?(Integer) && value["seq"].positive? &&
      value["digest"].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(value["digest"])
  end

  def self.valid_data?(data, sequence:, sender:)
    return false unless data.is_a?(Hash) && (data.keys - %w[previous owner session_id controllers players from]).empty?
    return false unless GameRoomParticipants.same?(data["owner"], sender) && !sender.to_s.empty?
    return false unless data["session_id"].is_a?(Integer) && data["session_id"] >= 0
    return false unless data["from"].is_a?(Integer) && data["from"] >= 0 && data["from"] <= sequence
    previous = data["previous"]
    return false unless previous == nil || (valid_anchor?(previous) && previous["seq"] < sequence && [0, sequence].include?(data["from"]))
    return false if data.key?('players') && !self.valid_players?(data['players'])
    seats = data["controllers"]
    seats.is_a?(Hash) && seats.size <= MAX_SEATS && seats.all? do |seat, kind|
      seat.is_a?(String) && !seat.empty? && seat.length <= 64 && %w[human bot].include?(kind)
    end
  end

  def self.valid_players?(players)
    players.is_a?(Array) && players.size.between?(1, MAX_SEATS) &&
      players.all? { |player| player.is_a?(String) && player.length.between?(1, 64) } &&
      GameRoomParticipants.unique(players).size == players.size
  end

  def players(session_id, initial:, before: Float::INFINITY)
    changes = replacements(session_id, initial: initial, before: before)
    changes.empty? ? initial.dup : changes.last.packet['data']['players'].dup
  end

  def replacements(session_id, initial:, before: Float::INFINITY)
    return [] unless @complete
    roster = initial
    @records.select do |record|
      data = record.packet['data']
      next false unless record.sequence < before && data['session_id'] == session_id.to_i && data['players']
      next false unless data['players'].length == initial.length
      changed = roster != data['players']
      roster = data['players']
      changed
    end
  end

  attr_reader :anchor, :records, :complete

  def initialize(founder:, records:, anchor:)
    @founder, @anchor, @records = founder.to_s, anchor, []
    @complete = anchor == nil
    return if anchor == nil
    indexed = records.each_with_object({}) { |r, all| all[r.sequence] = r if r.packet["kind"] == KIND }
    cursor = anchor
    while self.class.valid_anchor?(cursor)
      record = indexed[cursor["seq"]]
      return unless record && self.class.anchor(record) == cursor
      data = record.packet["data"]
      return unless self.class.valid_data?(data, sequence: record.sequence, sender: record.sender)
      @records.unshift(record)
      cursor = data["previous"]
      if cursor == nil
        @complete = true
        return
      end
    end
  end

  def owner_at(sequence)
    return nil unless @complete
    record = @records.reverse.find { |r| (r.packet["data"]["from"].zero? ? r.sequence : r.packet["data"]["from"]) <= sequence }
    record ? record.packet["data"]["owner"] : @founder
  end

  def controllers(session_id, before: Float::INFINITY)
    return {} unless @complete
    record = @records.reverse.find do |r|
      r.sequence < before && r.packet["data"]["session_id"] == session_id.to_i
    end
    record ? record.packet["data"]["controllers"].dup : {}
  end

  def epoch
    @anchor ? @anchor["digest"] : "initial"
  end

  def epoch_at(sequence)
    record = @records.reverse.find { |r| r.sequence < sequence }
    record ? self.class.anchor(record)["digest"] : "initial"
  end

  def current_owner
    owner_at(Float::INFINITY)
  end

  def authoritative_record?(record)
    @complete && @records.include?(record)
  end
end
