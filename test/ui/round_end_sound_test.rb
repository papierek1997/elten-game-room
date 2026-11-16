require_relative '../support/dealt_card_games'
require_relative '../support/bridge'
require_relative '../../lib/game_sounds'
include GameRoomTest::Assertions

def round_cues(table, before, after, viewer='Alice', event=table.events.last)
  Array(GameRoomSounds.event_cue(game:table.game, event:event, before_replay:before,
    after_replay:after, repository:table.repository, viewer:viewer))
end

%w[hearts bouillabaisse scopa].each do |id|
  table = GameRoomTest::DealtCardTable.new(id, count:id=='hearts' ? 4 : 2, options:{'score_limit'=>1000}, seed:17)
  table.finish_production_round
  after = table.replay
  before = table.game.replay(table.session, table.events[0...-1], table.repository)
  %w[Alice Spectator].each do |viewer|
    cues = round_cues(table,before,after,viewer)
    assert_equal(1,cues.count('round_finished'),"#{id}: missing or repeated end-of-round cue for #{viewer}")
  end
  assert_equal(nil,GameRoomRoundCues.missing_completion_cue(game:table.game,
    before_replay:nil,after_replay:after,history:after.history,cues:[]), 'Cold reconstruction plays the end signal')
  assert(!round_cues(table,after,after).include?('round_finished'), 'Repeated accepted event plays the end signal again')
  table.deal
  next_round = table.replay
  assert(!round_cues(table,after,next_round).include?('round_finished'), 'Starting another deal plays a completion signal')
end

bridge = GameRoomTest::BridgeTable.new
bridge.calls('P','P','P')
before = bridge.replay
bridge.call('P')
assert(round_cues(bridge,before,bridge.replay).include?('round_finished'), 'A thrown-in Bridge deal has no completion signal')

repo = GameRoomTest::DealtCardTable::Repository.new(%w[Alice Bob])
entry = GameRoomGames::HistoryEntry.new(kind: :round_result,event_id:2,key:'result:2')
make_replay = ->(event,history,state={}) { GameRoomGames::Replay.new(players:repo.players,
  accepted_events:[{'id'=>event}],history:history,state:state,draw:false) }
before = make_replay.call(1,[])
after = make_replay.call(2,[entry])
game = Class.new(GameRoomGames::Base) do
  def event_sound_cues(**); 'win1'; end
end.new
cue = ->(model,prev=before,next_replay=after) { Array(GameRoomSounds.event_cue(game:model,
  event:{'id'=>2},before_replay:prev,after_replay:next_replay,repository:repo,viewer:'Alice')) }
assert_equal(['win1'],cue.call(game), 'An existing round result sound is duplicated')
game = Class.new(GameRoomGames::Base) do
  def id; 'round_sound_contract'; end
end.new
after.winner = 'Alice'
assert_equal(['win_party'],cue.call(game), 'Final victory has an extra round sound')
after.winner = nil
assert_equal(['round_finished'],cue.call(game), 'An unknown future game needs framework registration')
pending_private = make_replay.call(2,[],{phase: :private_round_end})
assert_equal([],cue.call(game,before,pending_private), 'Unverified private end plays a completion signal')
%w[three_five_eight uno rummy domino mexican_train ninety_nine tysiac].each do |id|
  existing = GameRoomGames::CATALOG.build(id)
  assert(!existing.standard_round_end_sound?, "#{id}: existing round feedback policy was changed")
  assert_equal(nil,GameRoomRoundCues.missing_completion_cue(game:existing,before_replay:before,
    after_replay:after,history:[entry],cues:[]), "#{id}: fallback fills an intentional audience/tie silence")
end

%w[darts backgammon billiards krowa liars_dice blackjack_dice blackjack dice_poker].each do |id|
  consumer = GameRoomGames::CATALOG.build(id)
  kind = {'krowa'=>:solution,'liars_dice'=>:count,'blackjack_dice'=>:round,
    'blackjack'=>:settlement,'dice_poker'=>:settlement}.fetch(id,:notice)
  history = [GameRoomGames::HistoryEntry.new(kind:kind,event_id:2,key:id=='backgammon' ? 'game:2' : 'round:2')]
  prev = make_replay.call(1,[],{round:1})
  current = make_replay.call(2,history,{round:id=='darts' ? 2 : 1, phase:id=='billiards' ? :rack_end : :playing})
  assert(consumer.round_ended?(before_replay:prev,after_replay:current,history:history),"#{id}: custom public round boundary is missing")
end
assert_equal(nil,GameRoomSpatialSound.cue_position('round_finished',[1,0,0]),'Round signal follows the last actor instead of remaining centred')
assert(GameRoomSounds::ASSET_NAMES.include?('round_finished'), 'Shared sound allowlist omits the completion signal')
puts 'PASS round-end feedback: actual Hearts/Bouillabaisse/Scopa/Bridge rounds, observers, cold/repeated/deal silence, existing result priority, special boundaries and centred output'
