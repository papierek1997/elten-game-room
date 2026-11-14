require_relative '../../support/widget_presets'
game = GameRoomGames::Billiards.new
assert(!game.option_editor_definitions.find { |d| d.key == 'discipline' }.choices.any? { |c| c.value == 'practice' }, 'Internal practice leaked to new tables')
%w[friendly nine snooker carom].each do |discipline|
  options = game.table_creation_options('discipline' => discipline)
  preset = GameRoomTablePresets.build(game, {game_options: options, private_table: false})
  assert(GameRoomTablePresets.valid?(preset, game), 'A fresh billiards preset needs repair')
  assert(!preset['options'].key?('rack_seed'), 'A reusable preset fixed all future racks')
  draws = [42, 73]
  original = SecureRandom.method(:random_number)
  SecureRandom.define_singleton_method(:random_number) { |_limit| draws.shift || raise('Extra draw') }
  begin
    first = game.game_start_options(preset['options'], players: %w[Alice Bob])
    second = game.game_start_options(preset['options'], players: %w[Alice Bob])
    assert(first['rack_seed'] == 42 && second['rack_seed'] == 73, 'New games reused a previous rack seed')
    assert(game.new_game_options(first) == first, 'Validating recorded options changed the rack')
    assert(game.game_start_options(first, players: %w[Alice Bob], fixed: true) == first, 'Fixed game identity was rerolled')
  ensure
    SecureRandom.define_singleton_method(:random_number, original)
  end
end
puts 'PASS reusable billiards presets and a new rack seed only at a new game start'
