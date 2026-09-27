require_relative "../lib/game_room_localization"
require_relative "../lib/game_content"

GameRoomContent.registry.register_language(
  GameRoomContent::LanguageProfile.new(
    id: "en",
    label: GameRoomLocalization.translate("English"),
    alphabet: ("a".."z").to_a,
    normalizer: ->(text) { text.downcase }
  )
)

GameRoomContent.registry.register_language(
  GameRoomContent::LanguageProfile.new(
    id: "pl-PL",
    label: GameRoomLocalization.translate("Polish"),
    alphabet: %w[a ą b c ć d e ę f g h i j k l ł m n ń o ó p r s ś t u w y z ź ż],
    normalizer: ->(text) { text.downcase }
  )
)

GameRoomContent.registry.register_language(
  GameRoomContent::LanguageProfile.new(
    id: "ru-RU",
    label: GameRoomLocalization.translate("Russian"),
    alphabet: %w[а б в г д е ё ж з и й к л м н о п р с т у ф х ц ч ш щ ъ ы ь э ю я],
    normalizer: ->(text) { text.downcase }
  )
)
