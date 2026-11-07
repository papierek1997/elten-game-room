require_relative "../support/new_games_fixture"
require_relative "../../lib/game_room_localization"

GameRoomLocalization.boot(directory: File.expand_path("../../locale", __dir__),
  host_language: "ru", settings: { 'interface_language' => 'ru', 'known_languages' => ['ru'] })

def _(text)
  GameRoomLocalization.translate(text)
end

game = GameRoomGames::Monopoly.new
players = ['Player1', 'Player2']
state = game.send(:initial_state, players, game.default_options)
state[:board][1] = state[:board][1].merge(name: 'Воронеж', group: 'red')
state[:owners][1] = players.first
offer = game.send(:encode_trade_offer, target: 1, give_properties: [1], receive_cash: 435)
history = []
assert(game.send(:apply_trade, state, { 'id' => 1, 'action' => 'trade_offer', 'value' => offer },
  players.first, NewGames116Repository.new(players), history), 'Trade rejected')
expected = 'Player1 предложил обмен игроку Player2. Player1 отдаёт Player2: Воронеж (красная группа); Player2 отдаёт Player1: наличные (435).'
assert(history.last.text == expected, "Unexpected Russian trade: #{history.last.text}")
puts 'OK: Russian Monopoly trade history'
