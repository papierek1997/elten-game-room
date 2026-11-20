require_relative '../../../games/duck_racing_support/challenge_presentation'
require_relative '../../support/assertions'
extend GameRoomTest::Assertions

presentation = GameRoomDuckRacing::ChallengePresentation
names = {0=>'Alice', 1=>'Bob'}
view = {type: 'race_question', question: {seat: 0, field: :square}, player_names: names}
before = Marshal.dump(view)
assert_equal('Which square is Alice on?', presentation.prompt('race_question', view))
assert_equal(before, Marshal.dump(view), 'Duck question rewrote canonical player names')
practice = {type: 'sound_memory', practice: true, seats: [0,1], own: {ready: true}, waiting: [1], player_names: names}
projected = presentation.project(kind: 'sound_memory', view: practice, viewer: 0)
assert_equal('Ready. Waiting for: Bob.', projected[:announcement])
feedback = presentation.memory_feedback({seat: 0, position: 3, matched: true}, %w[Alice Bob])
assert_equal('Alice: 3.', feedback[:announcement])
assert_equal('Correct!', feedback[:result_announcement])
observer = {type: 'numbered_balls', player_names: names, turn_seat: 0, scores: {0=>12,1=>8}}
status = presentation.observation_status('numbered_balls', observer, totals: true)
assert(status.include?('Alice') && status.include?('Bob'), 'Duck inspected turn/score lost full names')
assert_equal({0=>'Alice',1=>'Bob'}, names, 'Duck labels changed account IDs')
puts 'PASS Duck challenge account question/wait/status/score names, unchanged live memory account and unchanged canonical public view'
