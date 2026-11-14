# encoding: UTF-8
require_relative '../../support/ui'

def _(text); text; end

require_relative '../../../games/darts'
require_relative '../../../lib/darts/client'

def assert(value, message)
  raise message unless value
end

darts_training_speech = []
capture_training_speech = lambda do |client|
  sink = darts_training_speech
  client.define_singleton_method(:speak) do |text, stop:, break_sequence:|
    sink << [text, stop, break_sequence]
  end
end

class DartsStartAudio
  attr_reader :updates, :ready_calls, :silence_calls, :warnings, :edge_calls, :limit_calls

  def initialize
    @updates, @ready_calls, @silence_calls, @warnings, @edge_calls, @limit_calls = [], 0, 0, [], 0, 0
  end

  def update(x, y, active:); @updates << [x, y, active]; end
  def ready; @ready_calls += 1; end
  def deadline_warning(seconds); @warnings << seconds; end
  def edge; @edge_calls += 1; end
  def limit; @limit_calls += 1; end
  def throw_dart; 0.4; end
  def silence; @silence_calls += 1; end
  def close; end
end

class DartsStartMouse
  def suspend; [[], false]; end
end

DartsStartReplay = Struct.new(:current_player, :state) do
  def finished?; false; end
end

now = 0.0
clock = -> { now }
audio = DartsStartAudio.new
game = GameRoomGames::Darts.new
client = GameRoomDarts::Client.new(Object.new, game, clock: clock,
  audio: audio, mouse: DartsStartMouse.new)
capture_training_speech.call(client)
state = {
  phase: :playing, seed: 'a' * 32, throw_index: 0, round: 1, dart: 1,
  options: {'difficulty'=>'normal', 'progressive'=>false, 'rounds'=>3,
    'time_limit'=>10, 'timeout_result'=>'auto', 'mouse_input'=>false, 'mode'=>'training'}
}
replay = DartsStartReplay.new('Alice', state)
client.before_wait(replay, 'Alice')
assert(client.instance_variable_get(:@aim_identity) == nil &&
  client.instance_variable_get(:@awaiting_start_identity) != nil,
  'a new dart began drifting before the player requested it')
assert(audio.updates.empty?, 'the locator started before the start trigger')

assert(client.send(:start_aim, now), 'Space-equivalent start trigger did not begin aiming')
assert(client.instance_variable_get(:@awaiting_start_identity) == nil &&
  client.instance_variable_get(:@aim_identity) != nil,
  'start trigger did not cross the waiting boundary exactly once')
assert(!audio.updates.empty?, 'start trigger did not start the locator')

now = 0.99
client.frame
assert(audio.ready_calls.zero?, 'ready sound played before the one-second lock')
now = 1.0
client.frame
assert(audio.ready_calls == 1, 'ready sound did not follow the player-triggered lock')
assert(darts_training_speech.map(&:first).include?('Time starts'),
  'training did not announce the beginning of active throw time')
now = 7.99
client.frame
assert(audio.warnings.empty?, 'deadline warning played before its threshold')
now = 8.0
client.frame
now = 8.2
client.frame
now = 9.0
client.frame
now = 10.0
client.frame
assert(audio.warnings == [3, 2, 1], 'deadline warnings were missing, repeated or out of order')
assert(darts_training_speech.map(&:first).select { |text| %w[3 2 1].include?(text) } == %w[3 2 1],
  'training did not speak the final three seconds exactly once and in order')

engine = client.instance_variable_get(:@engine)
edge_calls_before = audio.edge_calls
edge_speech_before = darts_training_speech.map(&:first).count('Target boundary')
client.instance_variable_set(:@outside_board, false)
engine.instance_variable_set(:@x, 1_001.0)
engine.instance_variable_set(:@y, 0.0)
client.send(:present_board_edge)
client.send(:present_board_edge)
engine.instance_variable_set(:@x, 999.0)
client.send(:present_board_edge)
engine.instance_variable_set(:@x, 1_001.0)
client.send(:present_board_edge)
assert(audio.edge_calls == edge_calls_before + 2, 'board edge repeated while outside or did not rearm after returning')
assert(darts_training_speech.map(&:first).count('Target boundary') == edge_speech_before + 2,
  'training did not speak each circular target crossing once')

engine.instance_variable_set(:@x, GameRoomDarts::Scoring::BOARD_LIMIT.to_f)
engine.instance_variable_set(:@y, 0.0)
assert(client.send(:move, :right, now) && audio.limit_calls == 1,
  'an arrow pressed against the hard cursor limit did not play its dedicated cue')
assert(client.send(:move, :right, now) && audio.limit_calls == 2,
  'a repeated arrow against the hard cursor limit did not replay its cue')
assert(darts_training_speech.map(&:first).count('Playfield boundary') == 2,
  'training did not speak every blocked attempt at the playfield limit')
audio_limit_before_return = audio.limit_calls
assert(client.send(:move, :left, now) && audio.limit_calls == audio_limit_before_return,
  'ordinary movement away from the hard cursor limit replayed the collision cue')

engine.instance_variable_set(:@x, 800.0)
engine.instance_variable_set(:@y, 0.0)
client.instance_variable_set(:@training_sector, :east)
sector_speech_before = darts_training_speech.length
client.send(:present_training_sector)
assert(darts_training_speech.length == sector_speech_before,
  'training repeated an unchanged cursor sector')
engine.instance_variable_set(:@x, 0.0)
engine.instance_variable_set(:@y, 800.0)
client.send(:present_training_sector)
client.send(:present_training_sector)
assert(darts_training_speech.drop(sector_speech_before).map(&:first) == ['up'],
  'training did not announce exactly one changed cursor sector')
client.send(:announce_training_position)
assert(darts_training_speech.last.first == 'up',
  'the explicit training repeat did not expose the current sector')

assert(client.send(:finish_throw, now, automatic: false), 'ready manual training throw was rejected')
assert(darts_training_speech.map(&:first).include?('Throw'),
  'training did not announce a manual throw')

automatic_audio = DartsStartAudio.new
automatic_client = GameRoomDarts::Client.new(Object.new, game, clock: clock,
  audio: automatic_audio, mouse: DartsStartMouse.new)
capture_training_speech.call(automatic_client)
now = 20.0
automatic_client.before_wait(DartsStartReplay.new('Alice', state), 'Alice')
assert(automatic_client.send(:start_aim, now), 'automatic-throw scenario did not start aiming')
now = 31.0
automatic_client.frame
assert(darts_training_speech.map(&:first).include?('Automatic throw'),
  'training did not announce the timeout throw')
automatic_client.close

state = state.merge(throw_index: 1, dart: 2)
client.before_wait(DartsStartReplay.new('Alice', state), 'Alice')
assert(client.instance_variable_get(:@aim_identity) == nil &&
  client.instance_variable_get(:@awaiting_start_identity) != nil,
  'the second dart inherited the previous running cursor')

client.close
puts 'PASS Darts start gate: trigger, training speech, ready lock, countdown, sectors and both boundaries'
