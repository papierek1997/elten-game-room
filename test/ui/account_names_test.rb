require_relative '../../lib/game_event_presenter'
require_relative '../../lib/room_presentation'
require_relative '../../lib/board_presentation'
require_relative '../../games/reversi'
require_relative '../../games/ludo'
require_relative '../../lib/game_simulation'
require_relative '../support/assertions'
include GameRoomTest::Assertions

game = Class.new(GameRoomGames::Base) do
  include GameRoomBoardPresentation
  def describe_event(*); ['Alice_Login bids 10.', 'Question: Alice_Login?']; end
end.new
repository = Object.new
def repository.event_id(event); event.fetch('__id'); end
spoken = []
presenter = GameRoomEventPresenter.new(game: -> { game }, repository: -> { repository }, program: -> { nil },
  viewer: -> { 'Viewer' }, client: -> { nil }, surface_state: -> { {} }, clock: -> { 0.0 }, covered: -> { false },
  speech: ->(text) { spoken << text }, trace: ->(*) {}, history_changed: ->(*) {}, session_changed: -> {})
entry = GameRoomGames::HistoryEntry.new(key: '1', text: 'Alice_Login bids 10.', event_id: 1, actor: 'Alice_Login', kind: :bid)
replay = GameRoomGames::Replay.new(players: %w[Alice_Login Bob_Login], current_player: 'Alice_Login', history: [entry], state: {})
event = {'__id'=>1, 'actor'=>'Alice_Login', 'action'=>'bid', 'value'=>'10'}
presenter.present_game_event(event, nil, replay, replay, nil)
assert_equal(['Alice_Login bids 10.', 'Question: Alice_Login?'], spoken)
assert_equal('Alice_Login bids 10.', entry.text)
spoken.clear
presenter.present_game_event(event, nil, replay, replay, nil, stage: {descriptions: ['Bob_Login deals.']})
assert_equal(['Bob_Login deals.'], spoken)
spoken.clear
presenter.present_turn_transition(entry, replay)
assert_equal(["It is Alice_Login's turn."], spoken)
spoken.clear
replay.winner = 'Alice_Login'
presenter.present_game_result(replay, nil)
assert_equal(['Alice_Login won the game.'], spoken)
assert_equal('Alice_Login', game.board_owner_label(replay, 0))
rows = RoomPresentation.user_rows(replay.players, owner: 'Alice_Login', players: replay.players, active: true)
assert(rows.first.label.start_with?('Alice_Login,') && rows.first.participant == 'Alice_Login')
reversi = GameRoomSimulation::Environment.new_game(game: GameRoomGames::Reversi.new, players: replay.players)
assert(reversi.game.surface_spec(reversi.replay, 'Viewer').cells.flatten.include?("Alice_Login's disc"))
ludo = GameRoomSimulation::Environment.new_game(game: GameRoomGames::Ludo.new, players: replay.players)
choices = ludo.game.custom_game_shortcuts(ludo.replay, 'Alice_Login').flat_map { |shortcut| shortcut.choices.to_a }
assert(choices.any? { |choice| choice.label.start_with?('Alice_Login,') })
puts 'PASS full account logins in native presentation, stages, turns, results, board ownership and pawn browsing'
