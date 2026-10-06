require_relative "../support/binary_rules_load"
using GameRoomLocalization::Translations

source = "This saved game needs %{count} seats, but tables support at most %{maximum}.".b
messages = {
  "en" => "This saved game needs 9 seats, but tables support at most 8.",
  "pl" => "Ta zapisana gra wymaga 9 miejsc, ale stoły obsługują najwyżej 8.",
  "cs" => "Tato uložená hra vyžaduje 9 míst, ale stoly podporují nejvýše 8.",
  "es" => "Esta partida guardada necesita 9 plazas, pero las mesas admiten como máximo 8.",
  "ru" => "Для этой сохранённой игры требуется 9 мест, но столы поддерживают не более 8."
}
messages.each do |language, expected|
  GameRoomTestLocalization.use_language(language)
  message = _(source) % { count: 9, maximum: 8 }
  raise "Incorrect #{language} table capacity message" unless message == expected
  raise "Invalid #{language} message encoding" unless (message + " — 1000 mil").valid_encoding?
end
puts "PASS table capacity warning: binary source and real EN/PL/CS/ES/RU catalogs"
