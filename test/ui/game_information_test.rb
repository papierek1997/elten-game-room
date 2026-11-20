require_relative '../support/dealt_card_games'
require_relative '../../lib/game_duration'
require_relative '../../lib/game_surfaces/realtime_information'
include GameRoomTest::Assertions

game = GameRoomGames::HeartsTable.new
repo = GameRoomTest::DealtCardTable::Repository.new(%w[Alice Bob Carol Dave])
events = [{ 'id'=>1, 'created_at'=>110, 'action'=>'deal' }, {'id'=>2, 'created_at'=>130, 'action'=>'play'},
  {'id'=>3, 'created_at'=>170, 'action'=>'play'}, {'id'=>4, 'created_at'=>200, 'action'=>'deal'}]
entry = ->(kind,id) { GameRoomGames::HistoryEntry.new(kind:kind,event_id:id,text:kind.to_s) }
replay = GameRoomGames::Replay.new(players:repo.players, accepted_events:events.take(2),
  history:[entry.call(:deal,1)], state:{options:game.default_options}, draw:false)
session = {'__id'=>1,'created_at'=>100}
time = ->(scope, now) { GameRoomDuration.text(scope, game:game, replay:replay, session:session, repository:repo, now:now) }
assert_equal('Game duration: 2 minutes, 5 seconds.', time.call('game',225))
assert_equal('Round duration: 1 minute, 55 seconds.', time.call('round',225))
replay.accepted_events = events.take(3)
replay.history << entry.call(:round_result,3)
assert_equal('Round duration: 1 minute.', time.call('round',225))
assert_equal('Round duration: 1 minute.', time.call('round',400))
replay.accepted_events = events
replay.history << entry.call(:deal,4)
assert_equal('Round duration: 25 seconds.', time.call('round',225))
replay.winner = 'Alice'
assert_equal('Game duration: 1 minute, 40 seconds.', time.call('game',500))
assert_equal('Round duration: 0 seconds.', time.call('round',500))
replay.winner = nil

# Use the native logical-time adapter, including a later pause which must not
# move a previously accepted round boundary backwards.
session.merge!('__server_started_at'=>1000,'__clock_offset'=>20,'__frozen_at'=>1145)
events[3].merge!('created_at'=>1120,'__clock_offset'=>10)
clock = GameRoomSessionClock.new(sample:->{1200}, elapsed:->{10}, wall:->{1200})
assert_equal('Game duration: 2 minutes, 5 seconds.', time.call('game',clock.now(session)))
assert_equal('Round duration: 15 seconds.', time.call('round',clock.now(session)))
events[3]['__game_time'] = 210
assert_equal('Round duration: 15 seconds.', time.call('round',clock.now(session)))
assert_equal('2 hours, 1 minute, 1 second', GameRoomDuration.format_seconds(7261))
assert_equal('Duration is unavailable.', GameRoomDuration.text('game', game:game,replay:replay,session:nil,repository:repo,now:225))

def empty_information_replay(game, options={})
  GameRoomGames::Replay.new(players:%w[Alice Bob], accepted_events:[], history:[],
    state:{options:game.normalize_options(options)}, draw:false)
end
{
 'hearts'=>100, 'spades'=>300, 'tysiac'=>1000, 'uno'=>500, 'scopa'=>11,
 'jass'=>1000, 'belote'=>1000, 'cribbage'=>121
}.each do |id, target|
  consumer = GameRoomGames::CATALOG.build(id)
  current = empty_information_replay(consumer)
  assert_equal(target, consumer.score_target(current), "#{id}: wrong target")
  source = GameRoomGames::GameShortcut.new(key:'s', label:'Scores', kind: :announcement, message:'Alice: 10.')
  once = consumer.decorate_information_shortcuts([source],current)
  again = consumer.decorate_information_shortcuts([source],current)
  assert_equal(once.map(&:message), again.map(&:message), 'Repeated build duplicates the suffix')
  assert_equal('Alice: 10.', source.message, 'Shared target mutates an owned shortcut')
  assert(once.first.message.end_with?(consumer.score_target_text(current)), 'Target is not last')
end

# A game may already own an unrelated information_shortcuts method. The shared
# decorator must never dispatch through that method with shortcut arguments.
legacy = Class.new(GameRoomGames::Base) do
  def shortcut_features; []; end
  def information_shortcuts(_state, _viewer); raise 'legacy information builder was called'; end
end.new
legacy_replay = empty_information_replay(legacy)
legacy_times = legacy.game_shortcuts(legacy_replay, 'Alice').select { |shortcut| shortcut.payload['duration_scope'] }
assert_equal(%w[game round], legacy_times.map { |shortcut| shortcut.payload['duration_scope'] },
  'Shared information decorator collided with a game-owned method')
blackjack = GameRoomGames::BlackjackDice.new
assert_equal(nil, blackjack.score_target(empty_information_replay(blackjack,'scoring'=>'chips')), 'Hidden point target added in chip mode')
backgammon = GameRoomGames::Backgammon.new
assert_equal(nil, backgammon.score_target_text(empty_information_replay(backgammon)), 'Single Backgammon game claims a zero point target')
backgammon_repo = GameRoomTest::DealtCardTable::Repository.new(%w[Alice Bob])
bound = backgammon.replay({'options'=>JSON.generate(backgammon.normalize_options('score_limit'=>7))},[],backgammon_repo)
assert_equal(7,backgammon.score_target(bound),'Backgammon target is not stored under state[:options]')

%w[axel_pong audio_ball].each do |id|
  consumer = GameRoomGames::CATALOG.build(id)
  repository = GameRoomTest::DealtCardTable::Repository.new(%w[Alice Bob])
  current = consumer.replay({'options'=>JSON.generate(consumer.default_options)},[],repository)
  spec = consumer.surface_spec(current,'Alice')
  command = id == 'axel_pong' ? :pong : :audio_ball
  message = GameSurfaces::RealtimeInformation.public_send(command,'scores',spec:spec,snapshot:nil)
  assert(message.end_with?(consumer.score_target_text(current)), "#{id}: live/replay score readout omits target")
end
categories = GameRoomGames::CATALOG.build('categories')
assert(!categories.duration_shortcuts?, 'Countries and Cities has duration bindings')
puts 'PASS on-demand game/round duration, round settlement/deal boundaries, frozen/restored logical clock, fixed/visible targets, score suffix ownership and realtime consumers'
