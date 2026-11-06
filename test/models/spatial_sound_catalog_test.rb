require_relative "../../games/catalog"

def assert(value, message); raise message unless value; end

# Only games whose event cues come from the moving player offer 3D sound.
# Audio, realtime and private-client games keep their own sound scene.
catalog = GameRoomGames::CATALOG
placed = catalog.ids.select { |id| catalog.build(id).player_spatial_audio? }
excluded = %w[audio_ball axel_pong krowa duck_racing categories quiz mania_pisania]
assert((excluded & catalog.ids).sort == excluded.sort, "Excluded game ids changed: #{excluded - catalog.ids}")
assert((placed & excluded).empty?, "Games without seat-based sounds offer 3D sound: #{placed & excluded}")
assert((catalog.ids - excluded - placed).empty?, "Turn-based games lost 3D sound: #{catalog.ids - excluded - placed}")
assert(%w[poker uno spades chess].all? { |id| placed.include?(id) }, "Core card/board games do not offer 3D sound")
puts "PASS 3D sound catalogue: #{placed.length} games opt in, audio/realtime/private-client games do not"
