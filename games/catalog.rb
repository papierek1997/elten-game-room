require_relative "base"
require_relative "board_game"
require_relative "card_game"
require_relative "four_in_a_row"
require_relative "tic_tac_toe"
require_relative "chess"
require_relative "checkers"
require_relative "reversi"
require_relative "ludo"
require_relative "spades"
require_relative "farkle"
require_relative "cat_head_tail"
require_relative "ninety_nine"
require_relative "mille_bornes"
require_relative "tysiac"
require_relative "three_five_eight"
require_relative "categories"
require_relative "monopoly"
require_relative "yahtzee"
require_relative "uno"
require_relative "poker"
require_relative "makao"
require_relative "quiz_party"
require_relative "rummy"
require_relative "domino"
require_relative "mexican_train"
require_relative "scrabble"
require_relative "taboo"
require_relative "biblios"
require_relative "battleship"
require_relative "mancala"
require_relative "krowa"
require_relative "axel_pong"
require_relative "audio_ball"
require_relative "war"
require_relative "scientific_war"
require_relative "registry"

module GameRoomGames
  CATALOG = GameRoomGames::Registry.new([
    GameRoomGames::FourInARow,
    GameRoomGames::TicTacToe,
    GameRoomGames::Chess,
    GameRoomGames::Checkers,
    GameRoomGames::Reversi,
    GameRoomGames::Ludo,
    GameRoomGames::Spades,
    GameRoomGames::Farkle,
    GameRoomGames::CatHeadTail,
    GameRoomGames::NinetyNine,
    GameRoomGames::MilleBornes,
    GameRoomGames::Tysiac,
    GameRoomGames::ThreeFiveEight,
    GameRoomGames::Categories,
    GameRoomGames::Monopoly,
    GameRoomGames::Yahtzee,
    GameRoomGames::Uno,
    GameRoomGames::Poker,
    GameRoomGames::Makao,
    GameRoomGames::QuizParty,
    GameRoomGames::Rummy,
    GameRoomGames::Domino,
    GameRoomGames::MexicanTrain,
    GameRoomGames::Scrabble,
    GameRoomGames::Taboo,
    GameRoomGames::Biblios,
    GameRoomGames::Battleship,
    GameRoomGames::Mancala,
    GameRoomGames::Krowa,
    GameRoomGames::AxelPong,
    GameRoomGames::AudioBall,
    GameRoomGames::War,
    GameRoomGames::ScientificWar
  ])
end
