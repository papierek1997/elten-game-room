require_relative '../support/tournament_public_service'
require_relative '../../lib/tournaments/public_service'
require_relative '../../lib/tournaments/server_workspace'
include TournamentPublicServiceSupport
include GameRoomTest::Assertions

game = GameRoomGames::CATALOG.build('taboo')
options = game.new_game_options(game.table_creation_options({}))
assert_equal([4, 6, 8], game.tournament_capabilities(options: options).fetch(:player_counts),
  'Generic/local team capabilities must not be narrowed')
assert_equal([4], T::ServerCapacity.supported_player_counts(game: game, options: options),
  'Public registration supports fixed pairs, not teams of three or four')
[6, 8].each do |count|
  sandbox do |context|
    context.actor = 'Owner'
    value = draft('taboo').merge('game_options'=>options, 'players_per_match'=>count,
      'participant_limit'=>count, 'participants'=>[], 'windows'=>[], 'starts_at'=>0, 'deadline_at'=>0)
    # The generic format still supports the separate local large-team path.
    assert(T::Publication.from_draft(draft:value, registry:GameRoomGames::CATALOG,
      publication_key:'local-large-team', rules:'Local teams', registration_opens_at:100,
      registration_closes_at:0, timezone:'UTC'))
    # The official workspace preflights public requests before delegating to
    # the generic service, which is also used by local large-team planners.
    workspace = T::ServerWorkspace.allocate
    workspace.instance_variable_set(:@registry, GameRoomGames::CATALOG)
    error = assert_raises(T::Publication::Invalid) do
      workspace.send(:publication_content!, {'draft'=>value, 'rules'=>'Public teams',
        'registration_opens_at'=>100, 'registration_closes_at'=>0, 'timezone'=>'UTC'})
    end
    assert_equal(:invalid_players_per_match, error.code)
    assert_equal([], context.inserts, 'An unsupported configuration wrote public data')
    assert_equal([], context.journal.list, 'An unsupported configuration stranded a journal intent')
    error = assert_raises(T::Publication::Invalid) do
      T::ServerCapacity.validate!(registry:GameRoomGames::CATALOG, game_id:'taboo', settings:value)
    end
    assert_equal(:invalid_players_per_match, error.code)
  end
end
sandbox do |context|
  value = draft('taboo').merge('game_options'=>options, 'players_per_match'=>4,
    'participant_limit'=>4, 'participants'=>[], 'windows'=>[], 'starts_at'=>0, 'deadline_at'=>0)
  result = context.service.publish(draft:value, intent_id:'public-pairs', rules:'Pairs still supported',
    registration_opens_at:100, registration_closes_at:0, timezone:'UTC')
  assert_equal('confirmed', result['status'])
end
puts 'PASS shared public match-size capability: Taboo fixed pairs only, no unsupported publication/start or stranded intent; generic large teams unchanged'
