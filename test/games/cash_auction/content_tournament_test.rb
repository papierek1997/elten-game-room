require_relative '../../support/settings_widget'
require_relative '../../support/tournament_public_ui'

include GameRoomTest::Assertions
GameRoomLocalization.boot(settings: {'interface_language'=>'en', 'known_languages'=>['en']})
game = GameRoomGames::CATALOG.build('cash_auction')
modern = game.new_game_options(game.table_creation_options('content_language_id'=>'pl-PL'))
legacy = game.normalize_options('content_language_id'=>'pl-PL', 'content_set_id'=>'quiz.witcher.books')
read_options = ->(row) { JSON.parse(row.fetch('settings_json')).fetch('game_options') }
rows = [modern, legacy].each_with_index.map do |options, index|
  row = TournamentPublicUI.publication(41 + index, game: game.id, options: options, 'players_per_match'=>3)
  assert_equal(options, read_options.call(row), 'Publication changed a pinned content identity')
  row
end
snapshot = TournamentPublicUI.snapshot(rows)
assert_equal(2, snapshot.fetch('announcements').length, 'The actual publication decoder rejected a valid source schema')
rows.each do |row|
  restored = snapshot.fetch('announcements').find { |entry| entry['__id'] == row['__id'] }
  assert_equal(read_options.call(row), read_options.call(restored), 'Reading a publication upgraded its options')
end

# New manifest/rules metadata must be admitted from validated control-only
# prototypes, and rejected when its recorded values or Ruby types disagree.
forged = Marshal.load(Marshal.dump(modern))
forged['content_pack_manifest'][0]['checksum'] = 'f' * 64
invalid = [forged, modern.merge('content_pack_manifest'=>{}),
  modern.merge('content_pack_ids'=>'quiz.wikidata.pl'),
  modern.merge('content_pack_ids'=>[modern['content_pack_ids'].first]),
  modern.merge('auction_rules_version'=>'2'), modern.merge('auction_rules_version'=>3),
  modern.merge('content_pack_manifest'=>modern['content_pack_manifest'].reverse)]
invalid.each_with_index do |options, index|
  assert_raises(GameRoomTournaments::Publication::Invalid) do
    TournamentPublicUI.publication(80 + index, game: game.id, options: options, 'players_per_match'=>3)
  end
end

class CashContentFixedStartApp < EltenGameRoom
  attr_reader :prepared
  def run_network_task(*, **); yield; end
  def alert(message); raise message; end
  def missing_live_session_members(_room); []; end
  def start_prepared_game(_row, state:, game:, participants:, options:, refreshed_room:)
    @prepared = options
  end
end

# Exercise the ordinary application's real Start boundary, rather than only
# invoking game_start_options directly. The fixed marker chooses that branch.
rows.each do |row|
  stored = read_options.call(row)
  [false, true].each do |fixed|
    table = {'__id'=>7, '__live_session_id'=>'cash-content-room', 'owner'=>'Alice',
      'game'=>game.id, 'game_options'=>JSON.generate(stored), 'status'=>'waiting'}
    table['tournament_match'] = {'fixture'=>'fixed-cash-content'} if fixed
    room = LobbyRepository::TableSnapshot.new(table: table, members: %w[Alice Bob Carol], bots: [], observers: [])
    state = GameRoomLifecycle::State.new(room: room, game: game, game_snapshot: nil, replay: nil)
    lobby = Object.new
    lobby.define_singleton_method(:owner_of) { |record| record.fetch('owner') }
    lobby.define_singleton_method(:snapshot_for) { |*, **| room }
    lobby.define_singleton_method(:playing?) { |_| false }
    app = CashContentFixedStartApp.new
    app.instance_variable_set(:@lobby, lobby)
    before = Marshal.dump(stored)
    app.send(:start_new_game, table, state: state)
    assert_equal(fixed ? stored : game.new_game_options(stored), app.prepared, 'Real Start chose the wrong fixed/new content schema')
    assert_equal(before, Marshal.dump(stored), 'Start preparation changed its recorded publication')
    if fixed && !stored.key?('auction_rules_version')
      assert_equal(false, app.prepared.key?('content_pack_ids'), 'An old fixed binding acquired a merged pool')
    else
      assert_equal(2, app.prepared['auction_rules_version'])
      assert_equal(3, app.prepared['content_pack_manifest'].length)
    end
  end
end

puts 'Cash Auction tournament sources: actual publication prototypes, strict metadata/checkbox types, old/new readback and the real ordinary/fixed Start boundary passed.'
