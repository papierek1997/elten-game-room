# encoding: UTF-8
require_relative "bot_names"

require_relative "game_room_localization"

module GameRoomParticipants
  using GameRoomLocalization::Translations
  BOT_PREFIX = "bot:".freeze
  BOT_PATTERN = /\Abot:(\d+):(\d+)(?::((?:pl|en)\d{2}))?\z/

  module_function

  def bot_id(table_id, number, name_token: nil)
    table = table_id.to_i
    index = number.to_i
    raise ArgumentError, "a bot requires a table id" if table <= 0
    raise ArgumentError, "a bot number must be positive" if index <= 0
    raise ArgumentError, "unknown computer name" if name_token != nil && GameRoomBotNames.name_for(name_token) == nil

    "#{BOT_PREFIX}#{table}:#{index}" + (name_token == nil ? "" : ":#{name_token}")
  end

  def bots_for(table_id, count, names: nil)
    Array.new([count.to_i, 0].max) { |index| bot_id(table_id, index + 1, name_token: names.to_a[index]) }
  end

  def bot?(participant)
    match = BOT_PATTERN.match(participant.to_s)
    match != nil && (match[3] == nil || GameRoomBotNames.name_for(match[3]) != nil)
  end

  def human?(participant)
    !bot?(participant)
  end

  def bot_number(participant)
    match = BOT_PATTERN.match(participant.to_s)
    match == nil ? nil : match[2].to_i
  end

  def bot_name_token(participant)
    BOT_PATTERN.match(participant.to_s)&.[](3)
  end

  def display_name(participant)
    name = GameRoomBotNames.name_for(bot_name_token(participant))
    return name if name != nil

    number = bot_number(participant)
    return participant.to_s if number == nil

    _("Computer %{number}") % { number: number }
  end

  def same?(first, second)
    first.to_s.casecmp(second.to_s) == 0
  end

  def includes?(participants, participant)
    participants.to_a.any? { |candidate| same?(candidate, participant) }
  end

  def humans(participants)
    unique(participants).select { |participant| human?(participant) }
  end

  # Preserve seat order and original spellings while excluding identities.
  # Array subtraction is case-sensitive, unlike the shared account contract.
  def excluding(participants, excluded)
    participants.reject { |participant| includes?(excluded, participant) }
  end

  def unique(participants)
    result = []
    participants.to_a.each do |participant|
      value = participant.to_s
      next if value.empty? || includes?(result, value)

      result << value
    end
    result
  end
end
