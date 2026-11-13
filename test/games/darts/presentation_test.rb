# encoding: UTF-8
def _(text); text; end

require_relative '../../../games/darts'
require_relative '../../../lib/darts/client'

def assert(value, message)
  raise message unless value
end

$darts_presentation_speech = []
def speak(text, stop:, break_sequence:)
  $darts_presentation_speech << [text, stop, break_sequence]
end

class DartsPresentationAudio
  attr_reader :calls

  def initialize
    @calls = []
  end

  def throw_dart; @calls << :throw; 0.4; end
  def impact(points, x:, y:); @calls << [:impact, points, x, y]; 0.3; end
  def result(won:); @calls << [won ? :win : :loss]; end
  def silence; end
  def close; @calls << :close; end
end

class DartsPresentationMouse
  def suspend; [[], false]; end
end

class DartsPresentationGame
  def describe_event(_event, _repository, _replay, _viewer); ['Alice scores 75 points.']; end
  def result_text(_replay); 'Alice won the game.'; end
end

class DartsPresentationRepository
  def event_id(event); event.fetch('__id'); end
end

DartsPresentationReplay = Struct.new(:finished, :winner, :players, :state) do
  def finished?; finished; end
end

now = 0.0
clock = -> { now }
audio = DartsPresentationAudio.new
client = GameRoomDarts::Client.new(Object.new, DartsPresentationGame.new, clock: clock,
  audio: audio, mouse: DartsPresentationMouse.new)
before = DartsPresentationReplay.new(false, nil, %w[Alice Bob], {throw_index: 0})
after = DartsPresentationReplay.new(true, 'Alice', %w[Alice Bob], {throw_index: 1})
event = {'__id' => 1, 'action' => 'darts_throw', 'value' => '0:300:0:500:m'}

client.event(event, before, after, 'Bob', DartsPresentationRepository.new)
assert(audio.calls == [:throw], 'a remote throw did not start with its release cue')
assert(client.presents_game_event?(event) && client.presents_game_result?(after),
  'shared speech can reveal a delayed Darts result early')

now = 1.39
client.frame
assert(audio.calls == [:throw] && $darts_presentation_speech.empty?,
  'impact or score arrived before the release and one-second flight pause')
now = 1.40
client.frame
assert(audio.calls.last == [:impact, 75, 300, 0] && $darts_presentation_speech.empty?,
  'the delayed board impact or its uncertainty boundary is wrong')
now = 1.69
client.frame
assert(audio.calls.none? { |call| call == [:loss] } && $darts_presentation_speech.empty?,
  'result presentation interrupted the board impact')
now = 1.70
client.frame
assert(audio.calls.last == [:loss], 'the losing participant did not receive consolation applause after impact')
assert($darts_presentation_speech.map(&:first) == ['Alice scores 75 points.', 'Alice won the game.'],
  'score or final result speech did not wait for the audible throw sequence')

local_audio = DartsPresentationAudio.new
local = GameRoomDarts::Client.new(Object.new, DartsPresentationGame.new, clock: clock,
  audio: local_audio, mouse: DartsPresentationMouse.new)
local.instance_variable_set(:@local_throw, {value: event['value'], impact_at: 3.0})
now = 2.0
local.event(event, before, after, 'Alice', DartsPresentationRepository.new)
assert(local_audio.calls.empty?, 'the throwing player heard the release cue twice after server confirmation')
now = 2.99
local.frame
assert(local_audio.calls.empty?, 'local impact ignored the release-time deadline')
now = 3.0
local.frame
assert(local_audio.calls.last == [:impact, 75, 300, 0], 'local confirmed throw lost its delayed impact')

client.close
local.close
puts 'PASS Darts presentation: release, one-second uncertainty, delayed impact/speech and result cues'
