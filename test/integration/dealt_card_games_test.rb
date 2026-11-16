require_relative '../support/dealt_card_games'
require_relative '../../lib/saved_game_archive'
include GameRoomTest::Assertions

class MemoryDealtArchive < GameRoomSavedGameArchive
  private
  def persist(row); row; end
end

%w[bouillabaisse scopa].each do |id|
  table = GameRoomTest::DealtCardTable.new(id, count:3)
  game = table.game
  5.times { table.play }
  before = Marshal.load(Marshal.dump(table.state))
  archive = MemoryDealtArchive.new(Object.new, owner:'Alice')
  snapshot = GameRoomSessionContracts::GameSnapshot.new(session:table.session,events:table.events)
  row = archive.put(game:game, table:{'owner'=>'Alice','name'=>'Fixture','private'=>true},
    snapshot:snapshot,repository:table.repository,now:1000)
  archive.validate(row,game:game)
  data = archive.restored_data(row,game:game,table_id:22,now:2000)
  session = {'__players'=>data[:players], 'options'=>row['options']}
  restored = game.replay(session,data[:events],GameRoomSavedGameArchive::ReplayRepository.new)
  assert_equal(before,restored.state,"#{id}: archive changed hand or score")
  replayer = game.incremental_replay(Marshal.load(Marshal.dump(table.replay)),table.session,[],table.repository)
  assert_equal(before,replayer.state,'empty incremental replay changed the game')
  previous = Marshal.load(Marshal.dump(table.replay))
  first = table.events.size
  table.play
  incremental = game.incremental_replay(previous,table.session,table.events.drop(first),table.repository)
  assert_equal(table.state,incremental.state,"#{id}: incremental reducer differs")
  actor=table.replay.current_player
  spec=game.surface_spec(table.replay,actor)
  own=table.state[:hands][actor]
  assert_equal(own,spec.zones.first.hand_order,"#{id}: hand order not supplied")
  expected = if id == 'bouillabaisse'
    own.sort_by { |card| GameRoomGames::Spades.new.send(:card_sort_key, card) }
  else
    own.sort_by { |card| [GameRoomGames::Scopa.card_value(card), %w[H S D C].index(card[1])] }
  end
  assert_equal(expected,spec.zones.first.cards.map(&:id),"#{id}: displayed card order or identity changed")
  nav=game.playable_card_navigation(table.replay,actor)
  assert(nav[:card_actions].keys.sort == game.legal_actions(table.replay,actor).map { |item| item['card_id'] }.sort,'playable navigation differs')
  keys=game.game_shortcuts(table.replay,actor).map { |shortcut| [shortcut.key,shortcut.modifiers] }
  %w[h c s t v z].each { |key| assert(keys.include?([key,[]]),"#{id}: missing #{key}") }
  assert(keys.uniq==keys && keys.include?(['z',[:shift]]) && keys.include?(['h',[:shift]]),'duplicate or missing sort shortcut')
  observation=game.bot_observation(table.replay,actor)
  assert_equal(own,observation['hand'],'bot cannot read own hand')
  assert(!observation.key?('hands'),'bot received other hands')
  old = table.replay.accepted_events.size
  bad={'id'=>10000,'actor'=>actor,'action'=>'play','value'=>'not-a-card'}
  assert_equal(old,game.replay(table.session,table.events+[bad],table.repository).accepted_events.size,'forged card accepted')
  assert_equal(old,game.replay(table.session,table.events+[bad.merge('action'=>'deal','value'=>'broken')],table.repository).accepted_events.size,'malformed deal accepted')
  [1,game.maximum_players+1].each do |count|
    invalid=GameRoomTest::DealtCardTable::Repository.new(Array.new(count) { |index| "Player#{index}" })
    session={'options'=>JSON.generate(game.default_options)}
    event={'id'=>1,'actor'=>'Player0','action'=>'deal','value'=>'1|0|'+'0'*32}
    rejected=game.replay(session,[event],invalid)
    assert(rejected.accepted_events.empty? && rejected.state[:phase]==:awaiting_deal,'unsupported roster dealt cards')
    assert(game.automatic_action(rejected,'Player0').nil?,'unsupported roster scheduled a deal')
  end
end
puts 'PASS dealt card integration: archives, incremental replay, hand identities, shared shortcuts, bot visibility, invalid events'
