# encoding: UTF-8
require 'thread'

module GameRoomParticipantNames
  MAX_NAME_CHARS = 64
  MAX_NAME_BYTES = 256
  NAMES_LOCK = Mutex.new

  def normalize_local_presentation_name(value)
    return nil unless value.is_a?(String) && value.bytesize <= 1024
    text = value.dup
    text.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::BINARY
    return nil unless text.valid_encoding?
    text = text.encode(Encoding::UTF_8)
    return nil if text.match?(/[\p{Cc}\u2028\u2029]/u)
    text = text.gsub(/[[:space:]]+/, ' ').strip
    return nil if text.length > MAX_NAME_CHARS || text.bytesize > MAX_NAME_BYTES
    text
  rescue EncodingError
    nil
  end

  def local_presentation_name(account = nil)
    NAMES_LOCK.synchronize do
      refresh_local_presentation_account
      own = account.nil? || account.is_a?(String) && account.bytesize <= MAX_NAME_BYTES && account.downcase == @local_presentation_account
      own ? @local_presentation_name.to_s.dup : ''
    end
  end

  def set_local_presentation_name(account:, name:)
    return false unless account.is_a?(String) && account.length <= MAX_NAME_CHARS && account.bytesize <= MAX_NAME_BYTES
    clean = normalize_local_presentation_name(name)
    raise ArgumentError, 'Invalid value' unless clean
    NAMES_LOCK.synchronize do
      refresh_local_presentation_account
      return false if @local_presentation_account.to_s.empty? || @local_presentation_account != account.downcase
      return true if @local_presentation_name.to_s == clean
      @local_presentation_name = clean.dup.freeze
      @local_presentation_revision = @local_presentation_revision.to_i + 1
    end
    true
  end

  def local_presentation_revision
    NAMES_LOCK.synchronize do
      refresh_local_presentation_account
      @local_presentation_revision.to_i
    end
  end

  private

  def refresh_local_presentation_account
    current = defined?(Session) ? Session.name.to_s : ''
    current = '' if current.length > MAX_NAME_CHARS || current.bytesize > MAX_NAME_BYTES
    current = current.downcase
    return if @local_presentation_account == current
    changed = !@local_presentation_name.to_s.empty?
    @local_presentation_account = current.dup.freeze
    @local_presentation_name = nil
    @local_presentation_revision = @local_presentation_revision.to_i + 1 if changed
  end
end
