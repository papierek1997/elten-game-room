require_relative '../../support/native_room_harness'
require_relative '../../../games/kosciane'
require_relative '../../../games/balut'
require_relative '../../../lib/saved_game_archive'
require_relative '../../support/contract_values'

class FiveDiceNativeRoom < NativeRoomHarness
  def assert_converged(stage)
    logs = users.map { |user| events(user) }
    assert(logs.uniq.one?, "#{stage}: native event logs diverged")
    ids = logs.first.map { |event| event['__id'] }
    assert(ids == ids.sort && ids == ids.uniq, "#{stage}: unordered or duplicate events")
    # FiveDiceMatch is an owned value object; compare all of its fields,
    # not the object identity of separately reconstructed model instances.
    snapshots = users.map { |user| GameRoomTest::ContractValues.canonical(GameRoomTest::ReplaySnapshot.capture(replay(user))) }
    assert(snapshots.uniq.one?, "#{stage}: replay values diverged")
  end
end

class FiveDiceContractArchive < GameRoomSavedGameArchive
  private
  def persist(_row); end
end

[GameRoomGames::Kosciane.new, GameRoomGames::Balut.new].each do |game|
  h = FiveDiceNativeRoom.new(game: game, users: %w[Alice Bob])
  h.start
  context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::LocalSecureSource.new, server_random: true)
  h.view('Alice').next_random_values = [1, 2, 4, 4, 6]
  h.submit('Alice', {'action'=>'roll'}, context:context)
  h.view('Alice').next_random_values = [5, 5]
  h.submit('Alice', {'action'=>'roll', 'die_ids'=>'d0,d1'}, context:context)
  assert(h.replay('Alice').state[:dice] == [4, 4, 5, 5, 6], "#{game.id}: reroll changed the retained multiset")
  assert(h.events('Alice').last.dig('__server_random', 'keep') == [4, 4, 6], "#{game.id}: native receipt omitted the kept dice")
  before = h.replay('Alice').accepted_events.size
  h.view('Alice').next_random_values = [6]
  h.write('Alice', [GameRoomServerRandom.command(action:'roll', count:1, sides:6, keep:[6,6,6,6], sort:true)])
  assert(h.replay('Alice').accepted_events.size == before, "#{game.id}: invented retained dice accepted")
  h.view('Alice').next_random_values = [3]
  h.write('Alice', [GameRoomServerRandom.command(action:'roll', count:1, sides:8, keep:[4,4,5,5], sort:true)])
  assert(h.replay('Alice').accepted_events.size == before, "#{game.id}: an eight-sided die was accepted")
  h.as('Alice') { h.transports.fetch('Alice').transfer_room_owner(h.table, 'Bob') }
  h.as('Bob') { h.transports.fetch('Bob').room_snapshot(h.table) }
  fresh = h.as('Bob') { h.repositories.fetch('Bob').session_for_table(h.table) }
  assert(fresh && fresh['__control_ready'], "#{game.id}: new owner did not publish the control epoch")
  h.instance_variable_set(:@session, fresh)
  h.submit('Alice', {'action'=>'score', 'category'=>game.id=='kosciane' ? 'pair' : 'choice'})
  h.assert_converged("#{game.id}: ownership transfer and scoring")

  repo = h.repositories.fetch('Bob')
  archive = FiveDiceContractArchive.new(nil, owner:'Bob')
  snapshot = repo.snapshot_for(h.session)
  row = archive.put(game:game, table:h.table.merge('owner'=>'Bob'), snapshot:snapshot, repository:repo, now:Time.now.to_i+1)
  target = FiveDiceNativeRoom.new(game:game, users:%w[Alice Bob])
  data = archive.restored_data(row, game:game, table_id:target.table['__id'], now:Time.now.to_i+30)
  target.as('Alice') do
    restored = target.repositories.fetch('Alice').restore_session(table:target.table, game:game.id,
      players:data[:players], options:row['options'], restore:data)
    assert(restored, "#{game.id}: archive upload failed")
  end
  remote = target.repositories.fetch('Bob').session_for_table(target.table, force:true)
  target.instance_variable_set(:@session, remote)
  target.assert_converged("#{game.id}: native archive restore")
  assert(target.replay('Bob').state[:current_player] == 'Bob', "#{game.id}: restore lost the turn")
  target.as('Alice') do
    target.transports.fetch('Alice').replace_game_player(target.table,
      session_id:remote['__id'], player:'Bob')
  end
  replaced = target.repositories.fetch('Alice').snapshot_for(remote)
  bot = replaced.session['__players'].last
  assert(GameRoomParticipants.bot?(bot), "#{game.id}: physical bot replacement failed")
  replay = game.replay(replaced.session, replaced.events, target.repositories.fetch('Alice'))
  assert(replay.current_player == bot, "#{game.id}: replacement lost its inherited turn")
  target.instance_variable_set(:@session, replaced.session)
  target.view('Alice').next_random_values = [1,2,3,4,5]
  command = GameRoomServerRandom.command(action:'roll', count:5, sides:6, sort:true)
  target.as('Alice') do
    target.repositories.fetch('Alice').append_events(session:replaced.session,
      sequence:target.repositories.fetch('Alice').next_sequence(replaced.session, replaced.events),
      events:[command], actor:bot, controller:true)
  end
  target.assert_converged("#{game.id}: restored replacement bot native roll")
  assert(target.replay('Alice').state[:turn_rolls] == 1, "#{game.id}: replacement bot cannot roll")
end
puts 'PASS both score-sheet games: native randomness, forged dice rejection, ownership transfer, archive restore and physical bot replacement'
