require_relative '../../lib/game_event_presenter'
require_relative '../../lib/room_presentation'
require_relative '../../lib/board_presentation'
require_relative '../../games/quiz_party'
require_relative '../../games/categories'
require_relative '../../games/reversi'
require_relative '../../games/ludo'
require_relative '../../lib/game_simulation'

def assert(value, message); raise message unless value; end

GameRoomParticipants.configure_display_name(account: 'Viewer', name: '')
GameRoomParticipants.remember_display_name('Alice', 'Anna Kowalska')
GameRoomParticipants.remember_display_name('Bob', 'Jan Nowak')
game = Class.new(GameRoomGames::Base) do
  include GameRoomBoardPresentation
  def describe_event(*); ['Anna Kowalska bids 10.', 'Question: Anna Kowalska?']; end
  def live_name_protected_texts(*); ['Question: Anna Kowalska?']; end
end.new
repository = Object.new
def repository.event_id(event); event.fetch('__id'); end
spoken = []
presenter = GameRoomEventPresenter.new(game: -> { game }, repository: -> { repository }, program: -> { nil },
  viewer: -> { 'Viewer' }, client: -> { nil }, surface_state: -> { {} }, clock: -> { 0.0 }, covered: -> { false },
  speech: ->(text) { spoken << text }, trace: ->(*) {}, history_changed: ->(*) {}, session_changed: -> {})
entry = GameRoomGames::HistoryEntry.new(key: '1', text: 'Anna Kowalska bids 10.', event_id: 1, actor: 'Alice', kind: :bid)
replay = GameRoomGames::Replay.new(players: %w[Alice Bob], current_player: 'Alice', history: [entry], state: {})
event = {'__id' => 1, 'actor' => 'Alice', 'action' => 'bid', 'value' => '10'}
presenter.present_game_event(event, nil, replay, replay, nil)
assert(spoken == ['Anna bids 10.', 'Question: Anna Kowalska?'], 'live presenter changed literal content or kept surname in action')
assert(entry.text == 'Anna Kowalska bids 10.', 'live shortening changed stored history')
spoken.clear
presenter.present_game_event(event, nil, replay, replay, nil, stage: {descriptions: ['Jan Nowak deals.']})
assert(spoken == ['Jan deals.'], 'staged event bypassed first-name presentation')
spoken.clear
presenter.present_turn_transition(entry, replay)
assert(spoken == ["It is Anna's turn."], 'turn announcement kept surname')
spoken.clear
replay.winner = 'Alice'
presenter.present_game_result(replay, nil)
assert(spoken == ['Anna Kowalska won the game.'], 'result lost full name')
assert(game.board_owner_label(replay, 0) == 'Anna', 'piece owner kept surname')
rows = RoomPresentation.user_rows(%w[Alice Bob], owner: 'Alice', players: %w[Alice Bob], active: true)
assert(rows.first.participant == 'Alice' && rows.first.label.start_with?('Anna Kowalska,'), 'participant list lost full label or canonical key')
spoken.clear
presenter.process_table_activity([], viewer: 'Viewer', text: ->(*) {})
chat = Struct.new(:id, :kind, :actor).new(1, 'chat', 'Alice')
presenter.process_table_activity([chat], viewer: 'Viewer', text: ->(*) { 'Anna Kowalska: Jan Nowak is my answer.' })
assert(spoken == ['Anna Kowalska: Jan Nowak is my answer.'], 'chat was shortened')

quiz = GameRoomGames::QuizParty.new
quiz.define_singleton_method(:current_question) { |_| {'prompt' => 'Who is Anna Kowalska?', 'correct' => 'Jan Nowak', 'wrong' => ['Anna Kowalska', 'Other', 'None']} }
protected = quiz.live_name_protected_texts(event, repository, replay, 'Viewer')
assert(GameRoomParticipants.shorten_announcement('Who is Anna Kowalska? Jan Nowak', participants: replay.players, protected_texts: protected) == 'Who is Anna Kowalska? Jan Nowak', 'quiz question or answer was renamed')
categories = GameRoomGames::Categories.new
categories.define_singleton_method(:review_items) { |_| [{answer: 'Anna Kowalska'}] }
categories.define_singleton_method(:round_category_ids) { |_| ['custom'] }
categories.define_singleton_method(:round_category_label) { |_, _| 'Jan Nowak' }
protected = categories.live_name_protected_texts(event, repository, replay, 'Viewer')
assert(protected == ['Anna Kowalska', 'Jan Nowak'], 'categories literal answers or custom categories not protected')
reversi = GameRoomSimulation::Environment.new_game(game: GameRoomGames::Reversi.new, players: %w[Alice Bob])
labels = reversi.game.surface_spec(reversi.replay, 'Viewer').cells.flatten
assert(labels.include?("Anna's disc") && !labels.any? { |label| label.include?('Kowalska') }, 'Reversi disc owner retained surname')
ludo = GameRoomSimulation::Environment.new_game(game: GameRoomGames::Ludo.new, players: %w[Alice Bob])
choices = ludo.game.custom_game_shortcuts(ludo.replay, 'Alice').flat_map { |shortcut| shortcut.choices.to_a }
assert(choices.any? { |choice| choice.label.start_with?('Anna,') }, 'Ludo pawn browser retained surname')
score_text = ludo.game.shortcut_feature_data(:material, ludo.replay, 'Alice').fetch(:message)
assert(score_text.include?('Anna Kowalska') && score_text.include?('Jan Nowak'), 'Ludo S counters lost full names')
puts 'PASS full names in history/results/lists, first names in live/staged/turn/piece presentation, unchanged chat and protected quiz/categories content'
