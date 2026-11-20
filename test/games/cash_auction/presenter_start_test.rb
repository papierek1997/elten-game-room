require_relative '../../support/assertions'
require_relative '../../../games/cash_auction'
require_relative '../../../lib/game_event_presenter'
extend GameRoomTest::Assertions

game = GameRoomGames::CashAuction.new
state = GameRoomCashAuction::Rules.initial(%w[Alice Bob], game.table_creation_options).merge(game_id: 1)
GameRoomCashAuction::Rules.draw!(state, category: 0, chest: false, now: 1000)
replay = GameRoomGames::Replay.new(players: state[:players], state: state, history: [], accepted_events: [])
repository = Object.new
def repository.event_id(event); event.fetch('id'); end
spoken, cues = [], []
covered = false
program = Object.new
original_play = GameRoomSounds.method(:play)
GameRoomSounds.define_singleton_method(:play) { |_program, cue, **| cues << cue }
presenter = GameRoomEventPresenter.new(game: -> { game }, repository: -> { repository }, program: -> { program },
  viewer: -> { 'Alice' }, client: -> { nil }, surface_state: -> { {} }, clock: -> { 1000.0 }, covered: -> { covered },
  speech: ->(text) { spoken << text }, trace: ->(*) {}, history_changed: ->(*) {}, session_changed: -> {})
begin
  presenter.process_new_events(replay, session: {'__id'=>1}, timer_now: 1000)
  assert_equal([:auction, 1, 1], game.required_decision_key(replay, 'Alice'), 'First auction has no pending decision')
  covered = true
  presenter.process_new_events(replay, session: {'__id'=>2}, timer_now: 1000)
  assert(cues.include?('ding'), 'A covered first auction did not announce the pending decision')
  before = cues.dup
  presenter.process_new_events(replay, session: {'__id'=>2}, timer_now: 1000)
  assert_equal(before, cues, 'An unchanged first auction repeated the decision alert')
  puts 'Cash Auction startup: foreground and covered first decisions, missing previous replay and unchanged-view deduplication through the real event presenter passed.'
ensure
  GameRoomSounds.define_singleton_method(:play, original_play)
end
