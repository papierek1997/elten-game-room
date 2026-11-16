require_relative '../../support/duck_challenge_native'

GameRoomLocalization.boot(settings: {'interface_language'=>'en'}, host_language: 'en')
spec = GameSurfaces::DartsSpec.new(game_id: 'darts', header: 'Darts playfield', players: ['Alice'],
  viewer: 0, current_player: 0, throw_index: 0, round: 1, dart: 1,
  difficulty: 'normal', scores: [0], active: true, finished: false, training: false)
surface = GameSurfaces.build(spec)
driver = DuckChallengeNativeDriver.new
form = driver.form(surface)
field = surface.fields.first

[[0x27, :right], [0x20, :throw]].each do |code, command|
  driver.frame(form)
  driver.frame(form, [[code, true, driver.raw([code])], [code, false], [0x11, true]], held: [0x11])
  assert(surface.input(form) == [command], "A modifier pressed after #{command} retroactively discarded the input")
  driver.frame(form, [[0x11, false]])

  driver.frame(form, [[0x11, true], [code, true, driver.raw([0x11, code])], [code, false], [0x11, false]])
  assert(surface.input(form).empty?, "A modified #{command} became gameplay after releasing the modifier")
end

driver.frame(form)
driver.frame(form, driver.tap(0x25))
assert(surface.input(form) == [:left] && surface.input(form).empty?, 'An ordinary press was lost or consumed twice')
surface.update_spec(spec.dup.tap { |copy| copy.active = false })
driver.frame(form)
driver.frame(form, driver.tap(0x27))
assert(surface.input(form).empty?, 'An observing player produced a movement')
assert(field.is_a?(EltenAPI::Controls::Button), 'Darts did not use the real native Button')
puts 'PASS native Darts field: press-time modifier snapshots, ordinary arrows/throw, no duplicates and spectator isolation'
