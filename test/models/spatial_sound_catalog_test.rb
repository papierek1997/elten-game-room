require_relative "../../games/catalog"
require_relative "../../lib/game_spatial_sound"

def assert(value, message); raise message unless value; end

# Games opt in through seat sounds or their own contact-position mapping.
# Audio, realtime and private-client games keep their own sound scene.
# Bingo draws come from the table, never from the host's seat.
catalog = GameRoomGames::CATALOG
placed = catalog.ids.select { |id| catalog.build(id).player_spatial_audio? }
excluded = %w[audio_ball axel_pong krowa duck_racing categories quiz mania_pisania bingo]
assert((excluded & catalog.ids).sort == excluded.sort, "Excluded game ids changed: #{excluded - catalog.ids}")
assert((placed & excluded).empty?, "Games without seat-based sounds offer 3D sound: #{placed & excluded}")
assert((catalog.ids - excluded - placed).empty?, "Turn-based games lost 3D sound: #{catalog.ids - excluded - placed}")
assert(%w[poker uno spades chess].all? { |id| placed.include?(id) }, "Core card/board games do not offer 3D sound")
assert(placed.include?('billiards') && catalog.build('billiards').respond_to?(:event_sound_positions), 'Billiards contact HRTF is missing from sound settings')

program = Object.new
def program.game_room_hrtf?(_game_id); true; end
repository = Object.new
def repository.actor_of(event, _session); event.fetch("actor"); end
replay = Struct.new(:players, :current_player).new(%w[Alice Bob], "Bob")
GameRoomSpatialSound.instance_variable_set(:@engine_ready, true)
position = ->(id, action) do
  GameRoomSpatialSound.event_position(program, catalog.build(id), {"action" => action, "actor" => "Bob"},
    replay, replay, repository, "Alice", {})
end
%w[go/place liars_dice/bid liars_dice/challenge roulette/bet cash_auction/bid cash_auction/all_in cash_auction/pass].each do |path|
  assert(position.call(*path.split("/")), "#{path}: player action lost its seat")
end
%w[bingo/draw liars_dice/deal roulette/spin cash_auction/wheel cash_auction/auction_start cash_auction/question cash_auction/answer].each do |path|
  assert(position.call(*path.split("/")).nil?, "#{path}: shared sound came from the host's seat")
end
puts "PASS 3D sound catalogue: #{placed.length} games opt in, audio/realtime/private-client games do not"
