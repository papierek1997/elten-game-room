require_relative '../../game_room_localization'

module GameRoomDartsRankings
  module TimeText
    module_function

    def seconds(milliseconds)
      value = format('%.2f', milliseconds.to_f / 1_000.0)
      GameRoomLocalization.primary_language == 'en' ? value : value.tr('.', ',')
    end

    def short(milliseconds)
      "#{seconds(milliseconds)} s"
    end
  end
end
