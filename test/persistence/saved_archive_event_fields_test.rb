require_relative '../support/dice_games'
require_relative '../../lib/saved_game_archive'
include DiceGamesSupport

class EventFieldsArchive < GameRoomSavedGameArchive
  private

  def persist(_row); end
end

game = GameRoomGames::DicePoker.new
players = %w[Alice Bob]
repository = DiceGamesSupport::Repository.new(players)
session = dice_session(game).merge('__players' => players)
events = [dice_event(1, 'Alice', 'roll', '1,2,3,4,5')]
archive = EventFieldsArchive.new(nil, owner: 'Alice')
row = archive.put(game: game, table: {'owner' => 'Alice', 'name' => 'Saved dice'},
  snapshot: Struct.new(:session, :events).new(session, events), repository: repository, now: 100)
check(archive.validate(row, game: game) == row, 'ordinary canonical archive was refused')

# A matching checksum is not authority for native-only replay metadata.
# These fields must be rejected at the shared archive boundary, before any
# game's decoder interprets them or raises an unrelated implementation error.
{'__server_random' => true, '__server_pool' => {'operation' => 'take'},
 '__payload' => {'action' => 'roll'}, 'unknown_field' => 'extra'}.each do |key, value|
  damaged = JSON.parse(JSON.generate(row))
  damaged.fetch('events').first[key] = value
  damaged['checksum'] = archive.send(:checksum, damaged)
  refused = false
  begin
    archive.validate(damaged, game: game)
  rescue ArgumentError => error
    refused = error.message == 'Invalid saved event'
  end
  check(refused, "noncanonical event field was not refused cleanly: #{key}")
end

# Logical timestamps are part of the saved format, not native-only metadata.
timed = JSON.parse(JSON.generate(row))
timed.fetch('events').first['game_time'] = 50
timed['checksum'] = archive.send(:checksum, timed)
check(archive.validate(timed, game: game) == timed, 'canonical logical timestamp was refused')
check(archive.restored_data(timed, game: game, table_id: 2, now: 200).fetch(:events).first['game_time'] == 50,
  'restoring lost the validated logical timestamp')
puts 'Saved archives reject native-only and unknown event fields before replay; canonical timestamps survive: OK'
