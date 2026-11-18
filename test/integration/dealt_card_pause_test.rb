require_relative '../support/dealt_card_games'
require_relative '../../lib/game_bots'
include GameRoomTest::Assertions

%w[belote jass hearts french_tarot cribbage bouillabaisse scopa].each do |id|
  table = GameRoomTest::DealtCardTable.new(id, count: id == 'cribbage' ? 2 : 4,
    options: id == 'french_tarot' ? {'round_limit' => 2} : {})
  table.finish_production_round
  assert(!table.replay.finished?, "#{id}: fixture finished a match rather than one round")
  table.events.last['created_at'] = 1000
  table.refresh
  clock = GameRoomRoundPause.new(table.repository)
  [1000, 1004].each do |now|
    assert(clock.active?(game: table.game, replay: table.replay, session: table.session, now: now),
      "#{id}: its production scoring history did not start the shared pause")
  end
  assert(!clock.active?(game: table.game, replay: table.replay, session: table.session, now: 1005), "#{id}: pause lasts over five seconds")
  assert(table.deal == :ok, "#{id}: the next legal deal changed")
  table.events.last['created_at'] = 1005
  table.refresh
  assert(!clock.active?(game: table.game, replay: table.replay, session: table.session, now: 1005), "#{id}: dealing restarted the pause")
  puts "PASS #{id}: production round, shared settlement boundary, exact deadline and next deal"
end
