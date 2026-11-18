require_relative '../../support/cheat'
require_relative '../../../lib/saved_game_archive'
include GameRoomTest::CheatFixture

class CheatArchive < GameRoomSavedGameArchive
  private def persist(_row); end
end

GameRoomGames::Cheat::VARIANTS.each do |variant|
  cheat_start(variant)
  @session['__players'] = @players
  archive = CheatArchive.new(nil, owner: @players.first)
  actor = @replay.current_player
  cheat_move(cheat_play(@replay.state[:hands].fetch(actor).take(1)))
  cheat_move(cheat_play(@replay.state[:hands].fetch(@replay.current_player).take(1))) if variant == 'suit'
  save = lambda do
    snapshot = Struct.new(:session, :events).new(@session, @events)
    row = archive.put(game: @game, table: {'owner' => @players.first, 'name' => 'Cheat'},
      snapshot: snapshot, repository: @repository, now: 100)
    restored = archive.restored_data(row, game: @game, table_id: 9, now: 200)
    session = {'options' => row['options'], '__players' => restored[:players]}
    replay = @game.replay(session, restored[:events], GameRoomSavedGameArchive::ReplayRepository.new)
    assert_equal(@replay.state, replay.state, "#{variant}: archive changed the exact pending phase")
    assert_equal(@replay.current_player, replay.current_player)
    cheat_conservation(replay.state)
    damaged = Marshal.load(Marshal.dump(row))
    damaged['events'].last['value'] = 'invalid'
    damaged['checksum'] = archive.send(:checksum, damaged)
    assert_raises(ArgumentError) { archive.validate(damaged, game: @game) }
  end
  save.call
  cheat_move(cheat_command('accept')) while @replay.state[:phase] == :reaction
  if variant == 'fixed_bluff'
    cheat_move(cheat_command('pass'))
    assert(!@replay.state[:passed].empty?, 'Bluff pass was not retained')
  end
  save.call
end
cheat_start('fixed_bluff')
@players = ['Alice', GameRoomParticipants.bot_id(2, 1), GameRoomParticipants.bot_id(2, 2)]
@repository = GameRoomTest::CheatFixture::Repository.new(@players)
@session['__players'] = @players
@events.first['actor'] = @players.first
@replay = @game.replay(@session, @events, @repository)
cheat_move(cheat_play(@replay.state[:hands].fetch(@players.first).take(1)))
cheat_move(cheat_command('accept')) while @replay.state[:phase] == :reaction
cheat_move(cheat_command('pass'))
cheat_move(cheat_play(@replay.state[:hands].fetch(@replay.current_player).take(1)))
archive = CheatArchive.new(nil, owner: 'Alice')
row = archive.put(game: @game, table: {'owner' => 'Alice', 'name' => 'Bluff'},
  snapshot: Struct.new(:session, :events).new(@session, @events), repository: @repository, now: 100)
restored = archive.restored_data(row, game: @game, table_id: 9, now: 200)
replay = @game.replay({'options' => row['options'], '__players' => restored[:players]}, restored[:events],
  GameRoomSavedGameArchive::ReplayRepository.new)
assert_equal(['Alice', GameRoomParticipants.bot_id(9, 1), GameRoomParticipants.bot_id(9, 2)], replay.players)
assert_equal([replay.players[1]], replay.state[:passed])
assert_equal(replay.players[2], replay.state[:last_packet][:actor])
assert_equal(replay.players[2], replay.state[:last_author])
cheat_conservation(replay.state)
puts 'PASS Cheat ordinary archive: all profiles, pending reactions, playing/opening and persistent Bluff passes; exact state, conservation, bot remapping and damaged-event refusal before restore'
