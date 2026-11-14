require_relative '../support/tournament_elimination_model'
require_relative '../../games/catalog'

checked = []
unsupported = []
GameRoomGames::CATALOG.ids.each do |id|
  game = GameRoomGames::CATALOG.build(id)
  options = game.normalize_options(game.default_options)
  count = game.tournament_capabilities(options: options).fetch(:player_counts).first
  unless count
    unsupported << id
    next
  end
  players = %w[Alice Bob Carol Dave Eve Frank Grace Henry].take(count)
  repository = TournamentEliminationModel::Repository.new(players)
  replay = game.replay({'__id'=>71, 'options'=>JSON.generate(options)}, [], repository)
  original = players.dup
  active = game.tournament_active_players(replay, options: options)
  raise "#{id}: wrong active roster #{active.inspect}" unless active == original
  active.clear
  raise "#{id}: active roster aliases replay participants" unless replay.players == original
  checked << id
end
raise 'Catalog coverage incomplete' unless (checked + unsupported).sort == GameRoomGames::CATALOG.ids.sort
puts "PASS tournament active participants from real replays for #{checked.size} games: #{checked.join(', ')}"
