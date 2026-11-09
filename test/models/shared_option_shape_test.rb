require_relative '../support/assertions'
require_relative '../../games/catalog'
include GameRoomTest::Assertions
GameRoomLocalization.boot(settings: {'interface_language' => 'en', 'known_languages' => ['en']})

def assert_multiple_choice_shapes(game, options)
  game.effective_option_definitions(options).each do |definition|
    next unless definition.kind.to_sym == :multiple_choice

    key = definition.key.to_s
    width = definition.choices.length
    full_mask = (1 << width) - 1
    wide = width > 63
    # Preserve scalar coercion, including finite floats. Wide checklists use
    # the same bits but store them as decimal text instead of a JSON number.
    [nil, 0, -1, 5.7, 1e22, '12', (1 << 80).to_s, 'not a number'].each do |value|
      mask = value.to_i & full_mask
      expected = wide ? mask.to_s : mask
      actual = game.normalize_options(options.merge(key => value))
      assert_equal(expected, actual[key], "#{game.id}/#{key}: incorrect #{width}-choice mask for #{value.inspect}")
    end
    [true, false, {}].each do |value|
      actual = game.normalize_options(options.merge(key => value))
      assert_equal(wide ? '0' : 0, actual[key], 'An unsupported mask type was not safely normalized')
      assert(!GameRoomOptionValues.valid?(definition, value), 'Strict published option validation was weakened')
    end
  end
end

invalid = [true, false, 1, 'teams', {}, [true], [{}], [[]], [Float::INFINITY], [Float::NAN]]
count = 0
GameRoomGames::CATALOG.ids.each do |id|
  game = GameRoomGames::CATALOG.build(id)
  defaults = game.default_options
  invalid.each do |seats|
    options = defaults.merge('team_seats' => seats)
    original = Marshal.dump(options)
    assert_raises(ArgumentError) { game.normalize_options(options) }
    assert_equal('The game settings are invalid.', game.validation_error(options, player_count: game.minimum_players))
    assert_raises(ArgumentError) { game.rules_options_text(options) }
    assert_equal(original, Marshal.dump(options), 'Shape validation mutated options')
    count += 1
  end
  [[], [nil, '0', 1.9, '1'], [0, 0, 1, 1], [-1, 2], ['invalid', '2junk']].each do |seats|
    normalized = game.normalize_options(defaults.merge('team_seats' => seats))
    assert_equal(seats.map(&:to_i), normalized['team_seats'], 'A nonthrowing historical conversion changed')
  end

  assert_multiple_choice_shapes(game, defaults)
  # An older Categories table still uses its original numeric mask.
  assert_multiple_choice_shapes(game, game.normalize_options({})) if id == 'categories'
  next if game.content_pack_kind.to_s.empty?

  [true, false, {}, []].each do |version|
    options = defaults.merge(GameRoomContent::PACK_VERSION_KEY => version)
    normalized = game.normalize_options(options)
    assert_equal(0, normalized[GameRoomContent::PACK_VERSION_KEY])
    assert(game.validation_error(options), 'Invalid content version passed raw validation')
    assert(game.validation_error(normalized), 'Invalid content version became a valid pack after normalization')
    assert_equal(nil, game.selected_content_pack(options))
  end
end
assert(count >= 350, 'The complete catalog shape matrix lost coverage')
puts "PASS #{count} rejected shared team shapes, historical coercions, masks and content versions across the game catalog"
