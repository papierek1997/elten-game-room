require_relative "../support/assertions"
require_relative "../support/code_quality"
include GameRoomTest::Assertions

source = "class Game\n def replay\n speak('UI')\n [1, 2].shuffle(random: random)\n end\nend\n"
found = GameRoomQuality.inspect_source('games/example.rb', source)
assert_equal(%w[model_ui host_shuffle], found.map { |item| item[:rule] })
baseline = found.to_h { |item| [GameRoomQuality.key(item), 1] }
assert(GameRoomQuality.new_findings(found, baseline).empty?, 'known debt rejected')
assert_equal(2, GameRoomQuality.new_findings(found + found, baseline).length, 'duplicate violation hidden by baseline')
assert(GameRoomQuality.inspect_source('games/example.rb', 'class Broken').any? { |item| item[:rule] == 'syntax' }, 'invalid syntax accepted')
assert(GameRoomQuality.inspect_source('games/example.rb', 'GameRoomRandom.shuffle(cards, random: rng)').empty?, 'host-compatible shuffle rejected')
GameRoomQuality::UI_ADAPTERS.each do |path|
  assert_equal(['host_shuffle'], GameRoomQuality.inspect_source(path, source).map { |item| item[:rule] }, 'presentation adapter excluded from unrelated checks')
  assert(GameRoomQuality.inspect_source(path, 'class Broken').any? { |item| item[:rule] == 'syntax' }, 'invalid UI adapter accepted')
end
assert_equal(['model_ui'], GameRoomQuality.inspect_source('games/krowa_support/private_reveal.rb', "alert('wrong layer')").map { |item| item[:rule] }, 'Krowa models must still reject UI calls')
puts 'PASS incremental quality checks and baseline accounting'

long = {file: 'lib/example.rb', rule: 'long_method', detail: 'run:100'}
baseline = {GameRoomQuality.key(long) => 1}
assert(GameRoomQuality.new_findings([long.merge(detail: 'run:90')], baseline).empty?, 'shrinking debt rejected')
assert_equal(1, GameRoomQuality.new_findings([long.merge(detail: 'run:101')], baseline).length, 'growing debt hidden')
assert_equal(1, GameRoomQuality.new_findings([long, long], baseline).length, 'duplicate long method hidden')
