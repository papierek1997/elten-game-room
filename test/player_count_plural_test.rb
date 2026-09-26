require_relative "../lib/game_room_localization"

ROOT = File.expand_path("..", __dir__)
METHOD = File.read(File.join(ROOT, "__app.rb"), encoding: "UTF-8")[/^  def invalid_player_count_message\(game, current_count\)\n.*?^  end\n/m]
raise "The player-count message method is missing" unless METHOD

Game = Struct.new(:minimum_players, :maximum_players)

class PlayerCountSpeaker
  class_eval(METHOD)

  def _(text)
    GameRoomLocalization.translate(text)
  end

  def n_(singular, plural, count)
    GameRoomLocalization.translate(singular, plural: plural, count: count)
  end
end

def assert_equal(actual, expected, label)
  raise "#{label}\nexpected: #{expected.inspect}\nactual:   #{actual.inspect}" unless actual == expected
end

def boot(language)
  GameRoomLocalization.boot(
    directory: File.join(ROOT, "locale"),
    host_language: language,
    settings: { "interface_language" => language, "known_languages" => [language] }
  )
end

speaker = PlayerCountSpeaker.new
range = Game.new(2, 8)
exact = Game.new(2, 2)

boot("en")
assert_equal(
  speaker.invalid_player_count_message(range, 1),
  "This game requires from 2 to 8 players. There is currently 1 user at the table.",
  "English singular"
)
assert_equal(
  speaker.invalid_player_count_message(range, 5),
  "This game requires from 2 to 8 players. There are currently 5 users at the table.",
  "English plural"
)
assert_equal(
  speaker.invalid_player_count_message(exact, 0),
  "This game requires exactly 2 players. There are currently 0 users at the table.",
  "English zero uses the plural"
)

boot("pl")
assert_equal(
  speaker.invalid_player_count_message(range, 1),
  "Ta gra wymaga od 2 do 8 graczy. Obecnie przy stole jest 1 użytkownik.",
  "Polish singular"
)
assert_equal(
  speaker.invalid_player_count_message(range, 3),
  "Ta gra wymaga od 2 do 8 graczy. Obecnie przy stole są 3 użytkownicy.",
  "Polish few"
)
assert_equal(
  speaker.invalid_player_count_message(range, 5),
  "Ta gra wymaga od 2 do 8 graczy. Obecnie przy stole jest 5 użytkowników.",
  "Polish many"
)
assert_equal(
  speaker.invalid_player_count_message(range, 22),
  "Ta gra wymaga od 2 do 8 graczy. Obecnie przy stole są 22 użytkownicy.",
  "Polish 22 follows the few form"
)
assert_equal(
  speaker.invalid_player_count_message(exact, 12),
  "Ta gra wymaga dokładnie 2 graczy. Obecnie przy stole jest 12 użytkowników.",
  "Polish 12 stays in the many form"
)

boot("es")
assert_equal(
  speaker.invalid_player_count_message(range, 1),
  "Este juego requiere entre 2 y 8 jugadores. Actualmente hay 1 usuario en la mesa.",
  "Spanish singular"
)
assert_equal(
  speaker.invalid_player_count_message(range, 5),
  "Este juego requiere entre 2 y 8 jugadores. Actualmente hay 5 usuarios en la mesa.",
  "Spanish plural"
)

boot("cs")
assert_equal(
  speaker.invalid_player_count_message(range, 1),
  "Počet hráčů pro tuto hru musí být v rozmezí 2 až 8. Aktuální počet uživatelů u stolu: 1.",
  "Czech keeps a count-independent sentence"
)

puts "Player-count plural: English, Polish, Spanish and Czech forms match the real method"
