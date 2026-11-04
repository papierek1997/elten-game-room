require_relative '../game_room_localization'

module GameRoomTyping
  module Languages
    SUPPORTED = %w[en pl cs es ru].freeze
    def self.visible
      known = GameRoomLocalization.known_languages & SUPPORTED
      known.empty? ? [GameRoomLocalization.primary_language] : known
    end

    def self.text_language(id)
      id.to_s[/_(en|cs|es|ru)\z/, 1] || 'pl'
    end
  end
end
