require_relative '../support/dealt_card_games'
require_relative '../support/bridge'
require_relative '../../lib/game_duration'
require_relative '../../lib/game_action_payload'
require_relative '../../lib/game_snapshot'
include GameRoomTest::Assertions

table = GameRoomTest::DealtCardTable.new('hearts',count:4,options:{'score_limit'=>1000},seed:17)
session = table.session.merge('created_at'=>100)
stamp = lambda do
  table.events.each_with_index { |event,index| event['created_at']=110+index*10 }
  table.refresh
end
read = -> { GameRoomDuration.text('round',game:table.game,replay:table.replay,session:session,repository:table.repository,now:10000) }
table.finish_production_round
stamp.call
expected = GameRoomDuration.format_seconds(table.events.last['created_at']-110)
before = Marshal.dump(table.replay)
assert_equal("Round duration: #{expected}.",read.call)
assert_equal(before,Marshal.dump(table.replay),'Duration mutated the rule replay')
table.deal
stamp.call
expected = GameRoomDuration.format_seconds(10000-table.events.last['created_at'])
assert_equal("Round duration: #{expected}.",read.call,'A real new Hearts deal did not reset the clock')

# A passed-out rubber deal has no score entry. The common completed-round
# phase stops the clock at its final accepted bid, without parsing speech.
bridge = GameRoomTest::BridgeTable.new
bridge.calls('P', 'P', 'P', 'P')
assert_equal(:round_complete, bridge.state[:phase])
assert_equal([bridge.events.first['id'], bridge.events.last['id']],
  bridge.game.round_timing_event_ids(bridge.replay, repository: bridge.repository),
  'Passed-out Bridge deal continues timing until the next deal')
bridge.deal
assert_equal([bridge.events.last['id'], nil],
  bridge.game.round_timing_event_ids(bridge.replay, repository: bridge.repository))

%w[spades bouillabaisse].each do |id|
  consumer = GameRoomGames::CATALOG.build(id)
  current = GameRoomGames::Replay.new(history:[GameRoomGames::HistoryEntry.new(kind: :deal, event_id: 2)],
    accepted_events:[{'id'=>2}, {'id'=>7}], state:{phase: :round_complete}, draw:false)
  assert_equal([2,7], consumer.round_timing_event_ids(current, repository: table.repository),
    "#{id}: scored round keeps ticking during the wait for the next deal")
end

# Compound typing actions are already decoded by the game. Timing metadata is
# reconstructed there and copied, not decoded again on the keypress thread.
game = GameRoomGames::ManiaPisania.new
repo = GameRoomTest::DealtCardTable::Repository.new(%w[Alice Bob])
options = game.normalize_options({})
events = GameRoomActionPayload.commands(game.id,{'action'=>'start','round'=>0,'seed'=>17}).each_with_index.map do |command,index|
  {'id'=>index+1,'actor'=>'Alice','action'=>command.action,'value'=>command.value,'created_at'=>150+index}
end
current = game.replay({'options'=>JSON.generate(options)},events,repo)
assert_equal(events,current.accepted_events,'Typing start fixture was refused')
assert_equal([events.last['id'],nil],current.round_timing)
assert_equal(current.round_timing,GameRoomSnapshot.copy(current).round_timing,'Owned snapshot dropped time metadata')

# These games advance a round at the score/settlement boundary rather than a
# separate deal. The last round still starts at the *previous* boundary.
%w[dice_poker blackjack_dice roulette audio_ball].each do |id|
  consumer = GameRoomGames::CATALOG.build(id)
  kind = id=='audio_ball' ? :set : %w[roulette dice_poker].include?(id) ? :settlement : :round
  history = [11,29].flat_map do |event_id|
    # Multiple award lines at one event are a single boundary.
    [GameRoomGames::HistoryEntry.new(kind:kind,event_id:event_id),GameRoomGames::HistoryEntry.new(kind:kind,event_id:event_id)]
  end
  replay = GameRoomGames::Replay.new(history:history,accepted_events:[],state:{},draw:false)
  assert_equal([29,nil],consumer.round_timing_event_ids(replay,repository:repo),"#{id}: new round boundary")
  replay.winner='Alice'
  assert_equal([11,29],consumer.round_timing_event_ids(replay,repository:repo),"#{id}: final round became zero-length")
end
puts 'PASS production Hearts round completion/redeal, unchanged state, accepted Typing Mania compound start, copied timing metadata and immediate-next-round/final boundaries'
