require_relative "../../../games/jass_support/jass_cards"
require_relative "../../support/cat_head_tail"
require_relative "../../../games/card_game"
cards = GameRoomGames::JassCards
raise unless cards::DECK.size == 36 && cards::DECK.uniq.size == 36
raise unless cards::DECK.all? { |card| GameRoomGames::CardGame::CARD_RANKS.include?(card[0]) && GameRoomGames::CardGame::CARD_SUITS.include?(card[1]) }
raise unless cards::DECK.map { |card| cards.encode(cards.decode(card)) } == cards::DECK
puts "PASS Jass card identifiers match Power Games"
