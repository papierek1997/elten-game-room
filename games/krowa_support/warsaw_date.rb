# encoding: UTF-8

module GameRoomKrowa
  module WarsawDate
    CET_OFFSET = 60 * 60
    CEST_OFFSET = 2 * 60 * 60
    SECONDS_PER_DAY = 24 * 60 * 60

    module_function

    def today_id(clock: -> { Time.now })
      utc = clock.call.getutc
      offset = daylight_saving_time?(utc) ? CEST_OFFSET : CET_OFFSET
      (utc + offset).strftime("%Y-%m-%d")
    end

    def daylight_saving_time?(utc)
      start_time = last_sunday_transition(utc.year, 3)
      end_time = last_sunday_transition(utc.year, 10)
      utc >= start_time && utc < end_time
    end

    def last_sunday_transition(year, month)
      last_day = Time.utc(year, month, 31, 1, 0, 0)
      last_day - (last_day.wday * SECONDS_PER_DAY)
    end

    private_class_method :daylight_saving_time?, :last_sunday_transition
  end
end
