require_relative '../../support/axel_pong_mouse'
require_relative '../../../lib/darts/mouse'

api = PongMouseApi.new
native = GameRoomPong::WindowsMouse.new(api: api, window: -> { 123 })
mouse = GameRoomDarts::Mouse.new(backend: native)

assert(mouse.sample(active: false, capture: true) == [[], false],
  'Darts did not capture the pointer while waiting between playable throws')
assert(api.point == api.middle, 'Darts did not anchor the captured pointer inside the Elten window')
api.point = [api.middle[0] + 48, api.middle[1] - 48]
assert(mouse.sample(active: false, capture: true) == [[], false] && api.point == api.middle,
  'pointer motion between turns escaped Elten or became a hidden aiming command')
mouse.suspend
assert(api.point == api.middle,
  'leaving Darts pointer capture restored an old position outside Elten')

assert(mouse.sample(active: true, capture: true) == [[], false], 'reactivating Darts mouse input jumped')
api.point = [api.middle[0] + 24, api.middle[1] - 12]
commands, clicked = mouse.sample(active: true, capture: true)
assert(commands == [:right, :right, :up] && !clicked,
  'active relative mouse movement did not retain the bounded Darts step mapping')

api.left = true
mouse.sample(active: false, capture: true)
_commands, clicked = mouse.sample(active: true, capture: true)
assert(!clicked, 'a mouse button held between turns became an unintended throw')
api.left = false
mouse.sample(active: true, capture: true)
api.left = true
_commands, clicked = mouse.sample(active: true, capture: true)
assert(clicked, 'a fresh left click did not start or throw after the button was released')

puts 'PASS Darts mouse: local capture between turns, no off-window restore, bounded movement and click edge'
