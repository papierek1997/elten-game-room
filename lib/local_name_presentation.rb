require 'digest'
require_relative 'game_participants'

class GameRoomLocalNamePresentation
  attr_reader :account, :runtime, :value, :revision

  def initialize(runtime:, account:)
    @runtime, @account = runtime, account.to_s.downcase.freeze
    @path = "receiver-#{Digest::SHA256.hexdigest(@account)}.json"
    @revision = 0
    stored = runtime.read_json(@path, default: nil)
    @value = normalize(stored['name']) if stored.is_a?(Hash) && stored['version'] == 1
  end

  def format(participant, form:)
    raise ArgumentError, 'Unknown name form' unless [:full, :first].include?(form)
    return GameRoomParticipants.display_name(participant) unless @value &&
      GameRoomParticipants.human?(participant) && GameRoomParticipants.same?(participant, @account)
    form == :full ? @value : @value.split(' ', 2).first
  end

  def token
    [object_id, @account, @revision]
  end

  def save(text)
    value = normalize(text)
    raise ArgumentError, 'Invalid value.' unless value
    persist(value)
  end

  def reset
    persist(nil)
  end

  private

  def normalize(text)
    return nil unless text.is_a?(String) && text.valid_encoding? && text.length <= 240 && text.bytesize <= 1024
    text = text.encode(Encoding::UTF_8)
    return nil if text.match?(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u)
    text = text.gsub(/\p{Space}+/u, ' ').strip
    return nil unless text.length <= 120 && text.bytesize <= 512 && text.split(' ').length >= 2
    text.freeze
  rescue EncodingError
    nil
  end

  def persist(value)
    return false if value == @value
    @runtime.write_json(@path, {'version' => 1, 'name' => value})
    @value = value
    @revision += 1
    true
  end

  module Entry
    def local_participant_name(participant, form: :full)
      service = local_name_presentation
      service ? service.format(participant, form: form) : GameRoomParticipants.display_name(participant)
    end

    def local_name_presentation
      service = @local_name_presentation
      service if service && self.class.app_runtime.equal?(service.runtime) &&
        GameRoomParticipants.same?(service.account, Session.name)
    end
  end
end
