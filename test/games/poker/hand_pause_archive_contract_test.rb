require_relative '../../support/clock_event_contract'
require_relative '../../support/card_timeout_restore'
require_relative '../../../games/poker'

def restore_poker_archive(f, saves, row)
  data = saves.restored_data(row, game: f.game, table_id: 0, now: Time.now.to_i)
  transport = f.h.transports['Alice']
  table = f.h.as('Alice') do
    transport.create_room(name: 'Restored Poker pause', game: f.game.id, owner: 'Alice',
      game_options: row['options'], capacity: 2)
  end
  remote = f.h.transports['Bob']
  found = remote.discover_rooms.find { |item| item['__id'] == table['__id'] }
  f.h.as('Bob') do
    assert(remote.establish_membership(table_id: table['__id'], owner: 'Alice', capacity: 2,
      user: 'Bob', table: found), 'Could not join the restored native room')
  end
  repository = f.h.repositories['Alice']
  session = f.h.as('Alice') do
    repository.restore_session(table: table, game: f.game.id, players: data[:players], options: row['options'], restore: data)
  end
  [table, session]
end

%w[holdem draw].product([0, 30], [0, 4000]).each do |variant, thinking_time, epoch|
  ClockEventContract.with_server_time do |time|
    original_clock = GameRoomClock.method(:now)
    GameRoomClock.define_singleton_method(:now) { Time.now.to_f + epoch }
    game = GameRoomGames::Poker.new
    f = ClockEventContract::Fixture.new(game, users: %w[Alice Bob],
      options: {'variant' => variant, 'thinking_time' => thinking_time})
    f.submit('Alice')
    time.call(1002)
    f.freeze('Alice', true)
    time.call(1062)
    f.freeze('Alice', false)
    time.call(1064)
    actor = f.replay.current_player
    f.submit(actor, game.legal_actions(f.replay(actor), actor).find { |item| item['action'] == 'fold' })
    original = f.replay
    assert(original.state[:hand_resume_at] == 1009 + epoch, 'Original hand pause uses the wrong logical clock')
    time.call(1066)
    f.freeze('Alice', true)
    snapshot = f.snapshot
    saves = SavedGames.new(TimedArchiveMemory.new, owner: 'Alice')
    row = saves.put(game: game, table: f.h.table, snapshot: snapshot,
      repository: f.h.repositories['Alice'], now: 1066)
    assert(row['game_time'] == 1006 + epoch, 'Saving did not preserve three seconds of pause')
    assert(row['events'].last['created_at'] == 1064 && row['events'].last['game_time'] == 1004 + epoch,
      'Archive failed to retain both raw server time and logical event time')
    time.call(2000)
    table, session = restore_poker_archive(f, saves, row)
    repository = f.h.repositories['Alice']
    f.h.users.each do |user|
      repo = f.h.repositories[user]
      restored = repo.snapshot_for(session)
      replay = game.replay(restored.session, restored.events, repo)
      label = "#{variant}/#{thinking_time}/#{epoch}/#{user}"
      assert(ClockEventContract.clock.now(restored.session) == 1006 + epoch, "#{label}: restoration changed logical time")
      assert(replay.state[:hand_resume_at] == 1009 + epoch,
        "#{label}: archive moved hand_resume_at from #{1009 + epoch} to #{replay.state[:hand_resume_at].inspect}")
      assert(replay.state[:hands] == original.state[:hands] && replay.state[:stacks] == original.state[:stacks],
        "#{label}: restoration changed cards or chips")
      context = GameRoomGames::ActionContext.new(now: 1008 + epoch, random_source: GameRoomRandom::SeededSource.new(1))
      assert(!game.automatic_action_due?(replay, 'Alice', context: context), "#{label}: pause elapsed too early")
      context.now = 1009 + epoch
      assert(game.automatic_action_due?(replay, 'Alice', context: context), "#{label}: remaining pause restarted after restore")
    end

    # Freeze after restoring, then save it a second time. Imported event times
    # must stay logical, while the new native boundary uses its current epoch.
    time.call(2001)
    f.h.as('Alice') { f.h.transports['Alice'].freeze_game(repository.snapshot_for(session).session) }
    time.call(2061)
    f.h.as('Alice') { f.h.transports['Alice'].freeze_game(repository.snapshot_for(session).session, frozen: false) }
    time.call(2062)
    f.h.as('Alice') { f.h.transports['Alice'].freeze_game(repository.snapshot_for(session).session) }
    snapshot = repository.snapshot_for(session)
    row2 = saves.put(game: game, table: table, snapshot: snapshot, repository: repository, now: 2062)
    assert(row2['game_time'] == 1008 + epoch && row2['events'] == row['events'], 'Repeated save retranslated historical time')
    time.call(3000)
    _table2, session2 = restore_poker_archive(f, saves, row2)
    snapshot2 = repository.snapshot_for(session2)
    replay2 = game.replay(snapshot2.session, snapshot2.events, repository)
    assert(replay2.state[:hand_resume_at] == 1009 + epoch, 'Repeated restore lost the hand boundary')
    assert(ClockEventContract.clock.now(snapshot2.session) == 1008 + epoch, 'Repeated restore lost remaining delay')
    time.call(3001)
    context = GameRoomGames::ActionContext.new(now: ClockEventContract.clock.now(snapshot2.session),
      random_source: GameRoomRandom::SeededSource.new(2), server_random: true)
    status, plan = game.action_for(game.automatic_action(replay2, 'Alice', context: context), replay2, 'Alice', context: context)
    assert(status == :ok, 'The twice-restored hand could not deal at its original deadline')
    f.h.as('Alice') do
      repository.append_events(session: snapshot2.session, sequence: repository.next_sequence(snapshot2.session, snapshot2.events),
        events: plan.events, actor: 'Alice')
    end
    fresh = repository.snapshot_for(session2)
    next_hand = game.replay(fresh.session, fresh.events, repository)
    assert(next_hand.state[:hand_number] == 2 && next_hand.state[:phase] == :betting, 'Native next deal failed after two restores')
    assert(next_hand.state[:turn_deadline] == 1039 + epoch, 'Next deal lost thinking time after restore') if thinking_time > 0
  ensure
    GameRoomClock.define_singleton_method(:now, original_clock)
  end
end

puts 'PASS Poker archive: ordinary Holdem/draw, timed/untimed, changed epoch, two native restores, intervening freeze, immutable timestamps, unchanged remaining delay and next deal'
