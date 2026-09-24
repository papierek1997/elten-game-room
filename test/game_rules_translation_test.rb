require "json"
require_relative "support/localization"

root = File.expand_path("..", __dir__)
mo = File.binread(File.join(root, "locale/PL.mo"))
count, originals, translations = mo.byteslice(8, 12).unpack("V3")
CATALOG = count.times.to_h do |i|
  size, offset = mo.byteslice(originals + 8 * i, 8).unpack("V2")
  key = mo.byteslice(offset, size).force_encoding("UTF-8")
  size, offset = mo.byteslice(translations + 8 * i, 8).unpack("V2")
  [key, mo.byteslice(offset, size).force_encoding("UTF-8")]
end

$missing_rules_translations = []
$rules_catalog_lookups = 0
GameRoomLocalization::Catalog.prepend(Module.new do
  def translate(source, **options)
    value = super
    $rules_catalog_lookups += 1
    $missing_rules_translations << source if value.nil? || value.empty?
    value
  end
end)
GameRoomTestLocalization.use_language(:pl)

def _(text)
  raise "Game Room called the host translator: #{text}"
end

files = %w[tic_tac_toe four_in_a_row spades farkle ninety_nine tysiac three_five_eight categories chess checkers reversi ludo monopoly yahtzee uno poker makao rummy domino mexican_train scrabble taboo biblios quiz_party]
require_relative "../games/base"
require_relative "../content/languages"
require_relative "../content/quiz_general_en"
require_relative "../content/quiz_pl_wikidata"
require_relative "../content/quiz_witcher_pl"
files.each { |file| require_relative "../games/#{file}" }
types = [GameRoomGames::TicTacToe, GameRoomGames::FourInARow, GameRoomGames::Spades,
  GameRoomGames::Farkle, GameRoomGames::NinetyNine, GameRoomGames::Tysiac,
  GameRoomGames::Categories, GameRoomGames::Chess, GameRoomGames::Checkers,
  GameRoomGames::Reversi, GameRoomGames::Ludo, GameRoomGames::Monopoly,
  GameRoomGames::Yahtzee, GameRoomGames::Uno, GameRoomGames::Poker, GameRoomGames::Makao,
  GameRoomGames::Rummy, GameRoomGames::Domino, GameRoomGames::MexicanTrain, GameRoomGames::Scrabble, GameRoomGames::Taboo, GameRoomGames::Biblios, GameRoomGames::QuizParty]
types.each do |type|
  game = type.new
  documents = game.rule_book(options: game.default_options).documents
  expected = ["Zasady", "Skróty klawiszowe w grze", "Ustawienia tego stołu"]
  raise "Wrong Polish document titles for #{game.id}: #{documents.map(&:title).inspect}" unless documents.map(&:title) == expected
  raise "Empty Polish rules for #{game.id}" if documents.any? { |document| document.text.strip.empty? }
  # Also cover labels hidden in the default table variant.
  game.option_definitions
end
additions = JSON.parse(File.read(File.join(root, "locale/game-rules-209-pl.json"), encoding: "UTF-8"))
additions.each do |english, polish|
  raise "Uncompiled Polish rule" unless CATALOG[english] == polish
  raise "Lost rule placeholder" unless english.scan(/%\{[^}]+\}/).sort == polish.scan(/%\{[^}]+\}/).sort
end
# Street/city deed names intentionally retain the regional proper names.
# Generic fields, currencies, headings and every rule still require Polish.
proper_names = GameRoomContent::MonopolyRegionalData::PROFILES.values.flat_map do |profile|
  profile[:layout].filter_map { |type, name, _group| name if type == :property }
end
raise "Rules never queried the actual MO catalog" unless $rules_catalog_lookups > 0
missing = $missing_rules_translations.uniq - proper_names
abort "Missing translations:\n#{missing.join("\n")}" unless missing.empty?
puts "Polish rules and settings translations passed for #{types.length} games"
