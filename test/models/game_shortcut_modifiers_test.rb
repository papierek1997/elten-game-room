require_relative '../../games/base'
require_relative '../support/assertions'
include GameRoomTest::Assertions

build = ->(modifiers) do
  GameRoomGames::GameShortcut.new(key: 's', label: 'Read scores',
    kind: :announcement, message: 'Scores', modifiers: modifiers)
end
assert(build.call(nil).modifiers == [], 'An unmodified shortcut gained a modifier')
input = ['shift', :control, :shift, :alt]
before = input.dup
assert(build.call(input).modifiers == [:alt, :control, :shift], 'Modifier normalization changed order, symbols or deduplication')
assert(input == before, 'Modifier normalization changed the caller array')
begin
  build.call([:control, :meta])
  raise 'Unsupported modifier was accepted'
rescue ArgumentError => error
  assert(error.message == 'a game shortcut contains an unsupported modifier', 'Unsupported modifier changed its error')
end
assert(!build.call([]).respond_to?(:normalize_shortcut_modifiers), 'Validation helper became a public shortcut action')
puts 'PASS shortcut modifiers: nil, canonical order, deduplication, caller ownership and unsupported modifier rejection'
