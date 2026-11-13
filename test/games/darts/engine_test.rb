# encoding: UTF-8
require_relative '../../../lib/darts/engine'

def assert(value, message)
  raise message unless value
end

now = 0.0
clock = -> { now }
first = GameRoomDarts::Engine.new(clock: clock).reset(seed: 'a' * 32, throw_index: 4,
  difficulty: 'normal', time_limit: 10, timeout_result: 'auto')
second = GameRoomDarts::Engine.new(clock: clock).reset(seed: 'a' * 32, throw_index: 4,
  difficulty: 'normal', time_limit: 10, timeout_result: 'auto')
assert(!first.ready?, 'throw was available before the one-second lock')
now = 0.8
first.step; second.step
assert(first.position == second.position && first.position != [0.0, 0.0], 'seeded drift is not deterministic or did not start immediately')
assert(first.finish == nil, 'manual throw bypassed the ready lock')
now = 1.0
assert(first.ready?, 'ready boundary was not reached after one second')
assert(first.nudge(1, 0), 'arrow nudge was rejected')
held = first.position
now += 0.2
first.step
assert(first.position == held, 'normal difficulty did not hold the corrected cursor briefly')
manual = first.finish
assert(manual[:index] == 4 && manual[:automatic] == false && manual[:time_ms] == 200,
  'manual result lost its throw identity or active aiming time')
assert(manual.values_at(:x, :y).all? { |value| value.between?(-1_000, 1_000) }, 'manual result escaped the board square')

now = 20.0
zero = GameRoomDarts::Engine.new(clock: clock).reset(seed: 'b' * 32, throw_index: 5,
  difficulty: 'hard', time_limit: 5, timeout_result: 'zero')
now = 26.0
zero.step
assert(zero.timed_out?, 'deadline did not expire')
miss = zero.finish(now, automatic: true)
assert(miss.values_at(:x, :y, :time_ms, :automatic) == [1_000, 1_000, 5_000, true],
  'zero-on-timeout did not create a bounded automatic miss')

now = 30.0
auto = GameRoomDarts::Engine.new(clock: clock).reset(seed: 'c' * 32, throw_index: 6,
  difficulty: 'easy', time_limit: 5, timeout_result: 'auto')
now = 36.0
auto.step
position = auto.position.map(&:round)
automatic = auto.finish(now, automatic: true)
assert(automatic.values_at(:x, :y) == position && automatic[:time_ms] == 5_000,
  'automatic timeout did not preserve the last cursor position')

puts 'PASS Darts engine: deterministic drift, ready lock, correction hold and timeout policies'
