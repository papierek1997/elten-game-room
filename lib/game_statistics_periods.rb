require "date"
require_relative "../games/krowa_support/warsaw_date"
require_relative "game_content"
require_relative "game_room_localization"

module GameRoomStatistics
  class Period
    attr_reader :key, :label, :from_date, :to_date

    def initialize(key:, label:, from_date:, to_date:)
      @key, @label = key, GameRoomContent.utf8(label)
      @from_date, @to_date = from_date, to_date
    end

    def from_day
      from_date&.strftime("%Y%m%d")&.to_i
    end

    def to_day
      to_date.strftime("%Y%m%d").to_i
    end
  end

  module Periods
    using GameRoomLocalization::Translations
    module_function

    def today(clock: -> { Time.at(GameRoomClock.now) })
      Date.iso8601(GameRoomKrowa::WarsawDate.today_id(clock: clock))
    end

    def options(today:, years:)
      result = [Period.new(key: "today", label: _("Today"), from_date: today, to_date: today)]
      [7, 30, 365].each do |length|
        result << Period.new(key: "last_#{length}",
          label: GameRoomContent.utf8(_("Last %{days} days (including today)")) % { days: length },
          from_date: today - (length - 1), to_date: today)
      end
      (years.to_a + [today.year]).uniq.sort.reverse_each do |year|
        result << Period.new(key: "year_#{year}", label: year.to_s,
          from_date: Date.new(year, 1, 1), to_date: Date.new(year, 12, 31))
      end
      result << Period.new(key: "all_time", label: _("All time"), from_date: nil, to_date: today)
      result
    end
  end
end
