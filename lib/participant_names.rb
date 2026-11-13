# encoding: UTF-8
require 'thread'

# This module belongs to the application's Runtime namespace. It contains only
# bounded presentation data; authenticated accounts remain the keys everywhere.
module GameRoomParticipantNames
  MAX_NAME_CHARS = 64
  MAX_NAME_BYTES = 256
  MAX_NAMES = 4096
  MAX_NAMES_BYTES = 524_288
  NAMES_LOCK = Mutex.new

  def normalize_display_name(value)
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

  def local_display_name
    names_lock.synchronize { @local_display_name.to_s.dup }
  end

  def configure_display_name(account:, name:)
    clean = normalize_display_name(name)
    raise ArgumentError, 'Invalid display name' unless clean
    names_lock.synchronize do
      if @names_account != account.to_s.downcase
        @participant_names, @participant_names_bytes = {}, 0
        @names_revision = @names_revision.to_i + 1
        @names_account = account.to_s.downcase.dup.freeze
      end
      @local_display_name = clean.dup.freeze
    end
    remember_display_name(account, clean)
    clean
  end

  # Call only after binding metadata to its native participant/envelope sender.
  # Empty is an explicit return to the account's ordinary ELTEN login.
  def remember_display_name(account, value, remote: false)
    name = normalize_display_name(value)
    return false unless name && account.is_a?(String) && !account.empty? && account.length <= 64 && account.bytesize <= 256 && !account.match?(/\p{Cc}/u)
    key = account.downcase
    names_lock.synchronize do
      return false if remote && key == @names_account
      @participant_names ||= {}
      @participant_names_bytes ||= 0
      return false if @participant_names.key?(key) && @participant_names[key] == name
      previous = @participant_names.delete(key)
      @participant_names_bytes -= key.bytesize + previous.bytesize if previous
      bytes = key.bytesize + name.bytesize
      while @participant_names.length >= MAX_NAMES || @participant_names_bytes + bytes > MAX_NAMES_BYTES
        retired, label = @participant_names.shift
        @participant_names_bytes -= retired.bytesize + label.bytesize
      end
      # Keep an explicit empty profile as bounded authenticated evidence too:
      # an untrusted public relay must not replace a cleared name.
      @participant_names[key.dup.freeze] = name.dup.freeze
      @participant_names_bytes += bytes
      @names_revision = @names_revision.to_i + 1
    end
    true
  end

  def names_revision
    names_lock.synchronize { @names_revision.to_i }
  end

  def custom_display_name(account)
    names_lock.synchronize do
      key = account.to_s.downcase
      return @local_display_name.dup if key == @names_account && !@local_display_name.to_s.empty?
      name = @participant_names&.[](key)
      name.dup if name && !name.empty?
    end
  end

  # Public discovery labels belong only to their displayed table. They never
  # replace names learned directly from an authenticated participant.
  def scoped_display_name(account, labels)
    known = names_lock.synchronize do
      key = account.to_s.downcase
      key == @names_account || @participant_names&.key?(key)
    end
    return display_name(account) if known || bot?(account)
    metadata_display_name(account, labels.to_h[account])
  end

  def short_name(participant)
    return display_name(participant) if bot?(participant)
    custom_display_name(participant)&.split(' ', 2)&.first || participant.to_s
  end

  def metadata_display_name(account, value)
    clean = normalize_display_name(value)
    clean ? (clean.empty? ? account.to_s : clean) : display_name(account)
  end

  # Shorten only known participant names in live game announcements. Verbatim
  # game content is masked before matching, and replacements never cascade.
  def shorten_announcement(text, participants:, protected_texts: [])
    source = text.to_s
    if source.encoding == Encoding::BINARY
      decoded = source.dup.force_encoding(Encoding::UTF_8)
      source = decoded if decoded.valid_encoding?
    end
    replacements = participants.to_a.first(32).to_h do |person|
      [display_name(person), short_name(person)]
    end.reject { |full, short| full.empty? || full == short }
    return source if replacements.empty?
    protected_ranges = protected_texts.to_a.first(256).uniq.filter_map do |part|
      next unless part.is_a?(String) && !part.empty?
      part
    end.flat_map do |part|
      ranges, cursor = [], 0
      while (index = source.index(part, cursor))
        ranges << (index...(index + part.length))
        cursor = index + part.length
      end
      ranges
    end
    pattern = Regexp.union(replacements.keys.sort_by { |name| -name.length })
    source.gsub(pattern) do |full|
      start, finish = Regexp.last_match.begin(0), Regexp.last_match.end(0)
      boundary = (start.zero? || !source[start - 1].match?(/[\p{L}\p{N}_]/u)) &&
        (finish == source.length || !source[finish].match?(/[\p{L}\p{N}_]/u))
      blocked = protected_ranges.any? { |range| start < range.end && finish > range.begin }
      boundary && !blocked ? replacements.fetch(full) : full
    end
  end

  private

  def names_lock
    NAMES_LOCK
  end
end
