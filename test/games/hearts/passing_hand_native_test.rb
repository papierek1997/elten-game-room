require_relative '../../support/duck_challenge_native'
require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions

table = GameRoomTest::DealtCardTable.new('hearts', count:4, seed:17)
game, actor = table.game, table.replay.current_player
surface = GameSurfaces.build(game.surface_spec(table.replay, actor))
driver = DuckChallengeNativeDriver.new
form = driver.form(surface)
field = surface.fields.first
actions = []
surface.on_action { |action| actions << action.to_h }
original = table.state[:hands][actor].dup
sent = []
3.times do |index|
  driver.frame(form)
  SpeechOutput.reset
  chosen = surface.instance_variable_get(:@cards)['hand'][field.index].id
  driver.frame(form, driver.tap(0x0d))
  assert_equal(index + 1, actions.size, 'Enter submitted no card or submitted twice')
  assert_equal(:ok, table.act(actor, actions.last))
  sent << chosen
  replay = table.replay
  assert_equal(original, table.state[:hands][actor], 'Presentation removed audit/exchange evidence')
  spec = game.surface_spec(replay, actor)
  assert_equal(12 - index, spec.zones.first.cards.size, 'A committed card remained in the displayed hand')
  assert((sent & spec.zones.first.cards.map(&:id)).empty?, 'An outgoing card can still be selected')
  expected = spec.zones.first.cards.map(&:label).join(', ')
  assert_equal("Your hand: #{expected}.", game.shortcut_feature_data(:hand, replay, actor)[:message])
  event = table.events.last
  assert_equal(['Card passed.'], game.describe_event(event, table.repository, replay, actor))
  other = replay.players.find { |player| player != actor }
  assert_equal([], game.describe_event(event, table.repository, replay, other), 'Another player heard private confirmation')
  surface.update_spec(spec)
  assert(surface.fields.first.equal?(field), 'A pass rebuilt the hand control')
  cursor = surface.take_cursor_announcement(0)
  assert_equal(field.options[field.index], cursor, 'Removal did not select/speak the surviving neighbour')
  surface.update_spec(spec)
  assert_equal(nil, surface.take_cursor_announcement(0), 'Unchanged hand repeated cursor speech')
  assert_equal(:invalid, table.act(actor, actions.last), 'A passed card could be submitted twice') if index < 2
end
# Completing the other packets delivers the actual incoming cards, without
# reviving an outgoing card or changing the selected sort order.
until table.state[:phase] != :passing
  other = table.replay.current_player
  assert_equal(:ok, table.act(other, game.legal_actions(table.replay, other).first))
end
surface.update_spec(game.surface_spec(table.replay, actor))
assert_equal(13, field.options.size)
assert((sent & surface.instance_variable_get(:@cards)['hand'].map(&:id)).empty?, 'The final exchange returned an outgoing card')
restored = GameSurfaces.build(game.surface_spec(table.replay, actor), state:surface.state)
assert_equal(field.options, restored.fields.first.options)
assert_equal([], game.describe_event({'id'=>999999, 'action'=>'pass_card', 'actor'=>actor}, table.repository, table.replay, actor),
  'A refused/nonexistent event announced success')
puts 'PASS native Hearts passing: Enter, one confirmation, immediate removal/H, cursor/control reuse, refused duplicates, exchange and reconstruction'
