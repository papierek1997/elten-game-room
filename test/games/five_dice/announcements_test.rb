require_relative '../../support/cat_head_tail'
require_relative '../../../games/kosciane'
require_relative '../../../games/balut'

players = %w[Alice Bob]
repository = CatHeadTailRepository.new(players)
game = GameRoomGames::Kosciane.new
session = {'options'=>JSON.generate(game.default_options)}
events = []
3.times do
  players.each do |actor|
    events << cht_event(events.size + 1, actor, 'roll', '6,6,6,6,6')
    events << cht_event(events.size + 1, actor, 'score', '6')
  end
end
replay = game.replay(session, events, repository)
assert(replay.history.count { |entry| entry.kind == :bonus } == 1, 'A shared row bonus was not announced exactly once')
assert(replay.history.any? { |entry| entry.text == 'Alice earns 30 bonus points for completing Sixes.' }, 'The row bonus has no recipient or amount')
assert(replay.history.any? { |entry| entry.text == 'Alice records 30 in Sixes, column 3.' }, 'The score has no column')
3.times { events << cht_event(events.size + 1, 'Alice', 'roll', '1,1,1,1,1') }
events << cht_event(events.size + 1, 'Alice', 'score', 'cross:2')
crossed = game.replay(session, events, repository)
assert(crossed.history.last.text == 'Alice loses 30 bonus points.', 'A school cross silently removed bonuses')
assert(crossed.history[-2].text == 'Alice crosses out Twos, column 1.', 'A cross sounds like a normal score')
assert(crossed.history.map(&:text) == game.replay(session, events, repository).history.map(&:text), 'Reconstructing the game repeats score feedback')

events = []
sample = GameRoomGames::FiveDiceMatch.new(players)
sample.categories.each do |category|
  faces = if %i[small_straight large_straight].include?(category)
    '2,3,4,5,6'
  elsif %i[two_pairs full_house].include?(category)
    '5,5,6,6,6'
  else
    Array.new(5, category.is_a?(Integer) ? category : 6).join(',')
  end
  players.each do |actor|
    events << cht_event(events.size + 1, actor, 'roll', faces)
    events << cht_event(events.size + 1, actor, 'score', category)
  end
end
replay = game.replay(session, events, repository)
assert(replay.accepted_events.size == events.size, "Column fixture rejected events: #{events - replay.accepted_events}")
assert(replay.history.count { |entry| entry.text == 'Alice earns 60 bonus points for completing column 1.' } == 1,
  "The completed column bonus is missing or repeated: #{replay.history.select { |entry| entry.kind == :bonus }.map(&:text)}")

balut = GameRoomGames::Balut.new
events = [cht_event(1, 'Alice', 'roll', '6,6,6,6,6'), cht_event(2, 'Alice', 'score', 'balut')]
replay = balut.replay({}, events, repository)
assert(replay.history[-2].text == 'Alice records 50 in Balut, entry 1.', 'Balut conflates the entry with game points')
assert(replay.history.last.text == 'Alice: game points: 0.', 'The changed game-point total was not announced')
events += [cht_event(3, 'Bob', 'roll', '4,4,4,4,4'), cht_event(4, 'Bob', 'score', 'fours')]
replay = balut.replay({}, events, repository)
assert(replay.history.last.text == 'Bob records 20 in Fours, entry 1.', 'An unchanged game total creates extra score speech')
[game, balut].each do |model|
  assert(model.event_sound_cues(event: {'action'=>'score'}, before_replay: nil, after_replay: replay,
    history: [], viewer: 'Alice', random_variant: 0) == 'cht-bank', 'Dice scoring uses a card-play effect')
end
puts 'PASS five-dice score announcements: row/column bonuses, loss, exact cell, Balut entry versus game points and non-card score cues'
