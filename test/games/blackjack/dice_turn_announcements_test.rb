require_relative '../../support/assertions'
require_relative '../../../games/blackjack_dice'
require_relative '../../../games/blackjack'
require_relative '../../support/blackjack'
require_relative '../../../lib/game_event_presenter'
include GameRoomTest::Assertions

game = GameRoomGames::BlackjackDice.new
repo = BlackjackChecksSupport::Repository.new(%w[Alice Bob])
session = {'__id'=>701, 'options'=>JSON.generate(game.default_options.merge('score_limit'=>10))}
events = [BlackjackChecksSupport.event(1,'Alice','roll','6,6'), BlackjackChecksSupport.event(2,'Alice','stand'),
  BlackjackChecksSupport.event(3,'Bob','roll','6,6'), BlackjackChecksSupport.event(4,'Bob','stand')]
before = game.replay(session, events.first(3), repo)
after = game.replay(session, events, repo)
assert_equal(['Bob', 'Bob', 2], [before.current_player, after.current_player, after.state[:round]])
assert(game.turn_transition_history_entry(before, after, event_id:4), 'The new round silently keeps the previous player')
initial = game.replay(session, [], repo)
assert(game.surface_spec(initial, 'Alice').zones.first.header.include?(game.turn_announcement(initial, 'Alice')),
  'The first player cannot hear whose turn begins')
program, spoken = Object.new, []
original_play = GameRoomSounds.method(:play)
GameRoomSounds.define_singleton_method(:play) { |*| nil }
presenter = GameRoomEventPresenter.new(game: -> { game }, repository: -> { repo }, program: -> { program },
  viewer: -> { 'Alice' }, client: -> { nil }, surface_state: -> { {} }, clock: -> { 100.0 }, covered: -> { false },
  speech: ->(text) { spoken << text }, trace: ->(*) {}, history_changed: ->(*) {}, session_changed: -> {})
begin
  presenter.process_new_events(initial, session:session)
  events.each_index do |index|
    spoken.clear
    replay = game.replay(session, events.take(index + 1), repo)
    presenter.process_new_events(replay, session:session)
    turns = spoken.count { |text| text == game.turn_announcement(replay, 'Alice') }
    assert_equal([1,3].include?(index) ? 1 : 0, turns, 'Missing or repeated turn speech through the real event presenter')
    spoken.clear
    presenter.process_new_events(replay, session:session)
    assert_equal([], spoken, 'Unchanged refresh repeated a turn announcement')
  end
  final = game.replay({'options'=>JSON.generate(game.default_options.merge('score_limit'=>1))},
    [BlackjackChecksSupport.event(1,'Alice','roll','6,6'), BlackjackChecksSupport.event(2,'Alice','stand'),
      BlackjackChecksSupport.event(3,'Bob','roll','1,1'), BlackjackChecksSupport.event(4,'Bob','stand')], repo)
  assert_equal(nil, game.turn_transition_history_entry(before, final, event_id:4), 'A finished match announced another turn')
ensure
  GameRoomSounds.define_singleton_method(:play, original_play)
end
puts 'PASS Blackjack Dice turn speech: initial field, normal handoff, same-player next round, unchanged-view deduplication and no post-result turn through the actual presenter; no live accounts or listening'
