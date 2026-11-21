require_relative '../support/clock_event_contract'
require_relative '../support/card_timeout_restore'
require_relative '../../lib/game_duration'

def mixed_restore(game,saves,row,at)
  h=NativeRoomHarness.new(game:game,users:%w[Alice Bob])
  restore=saves.restored_data(row,game:game,table_id:h.table['__id'],now:at)
  repo=h.repositories['Alice']
  session=h.as('Alice') do
    repo.restore_session(table:h.table,game:game.id,players:restore[:players],options:row['options'],restore:restore)
  end
  [h,session]
end

def mixed_submit(h,session,actor,selection)
  repository=h.repositories[actor]
  before=repository.snapshot_for(session)
  replay=h.game.replay(before.session,before.events,repository)
  context=GameRoomGames::ActionContext.new(now:ClockEventContract.clock.now(before.session),
    random_source:GameRoomRandom::SeededSource.new(14),server_random:true)
  status,plan=h.game.action_for(selection,replay,actor,context:context)
  assert(status==:ok,"Mixed restored action rejected: #{status}/#{selection.inspect}")
  h.as(actor) do
    repository.append_events(session:before.session,sequence:repository.next_sequence(before.session,before.events),
      events:plan.events,actor:actor)
  end
end

def mixed_durations(h, session, actor = 'Alice')
  repo = h.repositories.fetch(actor)
  snapshot = repo.snapshot_for(session)
  replay = h.game.replay(snapshot.session, snapshot.events, repo)
  %w[game round].map do |scope|
    GameRoomDuration.text(scope, game: h.game, replay: replay, session: snapshot.session,
      repository: repo, now: ClockEventContract.clock.now(snapshot.session))
  end
end

ClockEventContract.with_server_time do |time|
  game=GameRoomGames::NinetyNine.new
  f=ClockEventContract::Fixture.new(game,users:%w[Alice Bob],options:{'thinking_time'=>30})
  time.call(1001)
  f.submit('Alice')
  time.call(1002)
  f.freeze('Alice',true)
  time.call(1062)
  f.freeze('Alice',false)
  time.call(1064)
  rep=f.replay
  f.submit(rep.current_player,game.legal_actions(rep,rep.current_player,context:f.context(rep.current_player)).first)
  assert(f.replay.state[:turn_deadline]==1034,'First native action did not get its full logical limit')
  time.call(1065)
  f.freeze('Alice',true)
  saves=SavedGames.new(TimedArchiveMemory.new,owner:'Alice')
  row=saves.put(game:game,table:f.h.table,snapshot:f.snapshot,repository:f.h.repositories['Alice'],now:1065)
  assert(row['game_time']==1005 && row['events'].map{|event|event['game_time']}==[1001,1004],
    'First archive lost distinct pre/post-freeze event clocks')
  assert(row['game_started_at'] == 1000, 'Save did not distinguish the game start from the first deal')
  expected = ['Game duration: 5 seconds.', 'Round duration: 4 seconds.']
  assert(mixed_durations(f.h, f.h.session) == expected, 'Source durations are not distinct or include paused time')
  [nil, 0, 1006, '1000'].each do |start|
    invalid = row.merge('game_started_at' => start)
    invalid['checksum'] = saves.send(:checksum, invalid)
    begin
      saves.validate(invalid, game: game)
    rescue ArgumentError => error
      assert(error.message == 'Invalid saved game start time', 'Invalid origin failed for an unrelated reason')
    else
      raise 'An invalid game start was accepted'
    end
  end

  # A save from before this field still keeps any logical time that is known.
  legacy = row.reject { |key, _| key == 'game_started_at' }
  legacy['checksum'] = saves.send(:checksum, legacy)
  time.call(1500)
  old_room, old_session = mixed_restore(game, saves, legacy, 1500)
  assert(mixed_durations(old_room, old_session, 'Bob') == ['Game duration: 4 seconds.', 'Round duration: 4 seconds.'],
    'Legacy duration did not start at the first archived logical event')

  time.call(2000)
  h,session=mixed_restore(game,saves,row,2000)
  h.users.each do |user|
    assert(mixed_durations(h, session, user) == expected, "#{user}: restoring reset either reported duration")
  end
  time.call(2005)
  assert(mixed_durations(h, session, 'Bob') == ['Game duration: 10 seconds.', 'Round duration: 9 seconds.'],
    'The two restored durations did not advance from their original start times')
  snapshot=h.repositories['Alice'].snapshot_for(session)
  rep=game.replay(snapshot.session,snapshot.events,h.repositories['Alice'])
  actor=rep.current_player
  context=GameRoomGames::ActionContext.new(now:1010)
  mixed_submit(h,session,actor,game.legal_actions(rep,actor,context:context).first)
  snapshot=h.repositories['Alice'].snapshot_for(session)
  rep=game.replay(snapshot.session,snapshot.events,h.repositories['Alice'])
  assert(rep.state[:turn_deadline]==1040,'First action after restore used server2005 instead of logical1010')
  assert(snapshot.events.last['__clock_offset']==995,'New native action inherited an archived event clock')
  assert(!snapshot.events.last.key?('__game_time'),'New native action was projected as an archived event')
  time.call(2006)
  h.as('Alice'){h.transports['Alice'].freeze_game(snapshot.session)}
  time.call(2036)
  h.as('Alice'){h.transports['Alice'].freeze_game(h.repositories['Alice'].snapshot_for(session).session,frozen:false)}
  h.as('Alice'){h.transports['Alice'].freeze_game(h.repositories['Alice'].snapshot_for(session).session)}
  snapshot=h.repositories['Alice'].snapshot_for(session)
  row2=saves.put(game:game,table:h.table,snapshot:snapshot,repository:h.repositories['Alice'],now:2036)
  assert(row2['events'].take(2)==row['events'],'Second save rewrote already archived events')
  assert(row2['events'].last.values_at('created_at','game_time')==[2005,1010],
    'Mixed old/new archive did not preserve the new event clock independently')
  assert(row2['game_time']==1011,'Second save did not exclude the intervening freeze')
  assert(row2['game_started_at'] == 1000, 'Resaving replaced the original game start')

  time.call(4000)
  h2,session2=mixed_restore(game,saves,row2,4000)
  h2.users.each do |user|
    snapshot=h2.repositories[user].snapshot_for(session2)
    rep=game.replay(snapshot.session,snapshot.events,h2.repositories[user])
    assert(rep.state[:turn_deadline]==1040 && ClockEventContract.clock.now(snapshot.session)==1011,
      "#{user}: second native restore changed the remaining 29 seconds")
    assert(rep.accepted_events.length==row2['events'].size,'Second restore rejected mixed-era history')
    assert(mixed_durations(h2, session2, user) == ['Game duration: 11 seconds.', 'Round duration: 10 seconds.'],
      "#{user}: another save and restore lost already elapsed time")
    assert(!game.automatic_action_due?(rep,'Alice',context:GameRoomGames::ActionContext.new(now:1039)),
      'Restored timeout became due early')
    assert(game.automatic_action_due?(rep,'Alice',context:GameRoomGames::ActionContext.new(now:1040)),
      'Restored timeout did not become due on its original boundary')
  end
  time.call(4029)
  snapshot=h2.repositories['Alice'].snapshot_for(session2)
  rep=game.replay(snapshot.session,snapshot.events,h2.repositories['Alice'])
  selection=game.automatic_action(rep,'Alice',context:GameRoomGames::ActionContext.new(now:1040))
  mixed_submit(h2,session2,'Alice',selection)
  after=h2.repositories['Bob'].snapshot_for(session2)
  assert(after.events.size==row2['events'].size+1 && after.events.last['action']=='turn_timeout',
    'The twice-restored limit did not accept exactly one native timeout')
  assert(game.replay(after.session,after.events,h2.repositories['Bob']).accepted_events==after.events,
    'The remote view rejected the resumed native timeout')
end
puts 'PASS mixed native archive clocks: game and round duration across two restores and pauses, legacy save, remote view, unchanged 29-second remainder, one accepted timeout'
