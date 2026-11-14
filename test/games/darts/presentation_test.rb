# encoding: UTF-8
require_relative '../../support/ui'

def _(text); text; end

require_relative '../../../games/darts'
require_relative '../../../lib/darts/client'

def assert(value, message)
  raise message unless value
end

darts_presentation_speech = []
capture_presentation_speech = lambda do |client|
  sink = darts_presentation_speech
  client.define_singleton_method(:speak) do |text, stop:, break_sequence:|
    sink << [text, stop, break_sequence]
  end
end

class DartsPresentationAudio
  attr_reader :calls

  def initialize
    @calls = []
  end

  def throw_dart; @calls << :throw; 0.4; end
  def impact(points, x:, y:); @calls << [:impact, points, x, y]; 0.3; end
  def quality(points); @calls << [:quality, points]; 0.4; end
  def result(won:); @calls << [won ? :win : :loss]; 0.25; end
  def silence; end
  def close; @calls << :close; end
end

class DartsPresentationMouse
  def suspend; [[], false]; end
end

class DartsPresentationGame
  def describe_event(event, _repository, _replay, _viewer)
    match = GameRoomGames::Darts::THROW_PATTERN.match(event.fetch('value'))
    ["Alice scores #{GameRoomDarts::Scoring.points(match[2].to_i, match[3].to_i)} points."]
  end
  def result_text(_replay); 'Alice won the game.'; end
  def throw_prompt_text(replay); "Round #{replay.state[:round]} throw #{replay.state[:dart]}"; end
end

class DartsPresentationRepository
  def event_id(event); event.fetch('__id'); end
end

DartsPresentationReplay = Struct.new(:finished, :winner, :players, :state, :current_player) do
  def finished?; finished; end
end

now = 0.0
clock = -> { now }
audio = DartsPresentationAudio.new
client = GameRoomDarts::Client.new(Object.new, DartsPresentationGame.new, clock: clock,
  audio: audio, mouse: DartsPresentationMouse.new)
capture_presentation_speech.call(client)
before = DartsPresentationReplay.new(false, nil, %w[Alice Bob], {throw_index: 0}, 'Alice')
after = DartsPresentationReplay.new(true, 'Alice', %w[Alice Bob], {throw_index: 1}, nil)
event = {'__id' => 1, 'action' => 'darts_throw', 'value' => '0:300:0:500:m'}
score = GameRoomDarts::Scoring.points(300, 0)

client.event(event, before, after, 'Bob', DartsPresentationRepository.new)
assert(audio.calls == [:throw], 'a remote throw did not start with its release cue')
assert(client.presents_game_event?(event) && client.presents_game_result?(after),
  'shared speech can reveal a delayed Darts result early')
assert(client.presentation_pending?, 'finished view was exposed before the delayed throw presentation')

now = 0.89
client.frame
assert(audio.calls == [:throw] && darts_presentation_speech.empty?,
  'impact or score arrived before the release and half-second flight pause')
now = 0.90
client.frame
assert(audio.calls.last == [:impact, score, 300, 0] && darts_presentation_speech.empty?,
  'the delayed board impact or its uncertainty boundary is wrong')
now = 1.19
client.frame
assert(audio.calls.none? { |call| call == [:loss] } && darts_presentation_speech.empty?,
  'result presentation interrupted the board impact')
now = 1.21
client.frame
assert(audio.calls.last == [:quality, score] && darts_presentation_speech.empty?,
  'the score-quality cue did not wait for the physical board impact')
now = 1.60
client.frame
assert(darts_presentation_speech.empty?, 'score speech interrupted the quality cue')
now = 1.61
client.frame
assert(audio.calls.last == [:loss], 'the losing participant did not receive consolation applause after the score cue')
assert(darts_presentation_speech.map(&:first) == ["Alice scores #{score} points.", 'Alice won the game.'],
  "score or final result speech did not wait for the audible throw sequence: #{darts_presentation_speech.inspect}")
assert(client.presentation_pending?, 'finished view was exposed while the result recording was still playing')
now = 1.85
client.frame
assert(client.presentation_pending?, 'result recording tail was shortened')
now = 1.86
client.frame
assert(!client.presentation_pending?, 'finished view remained deferred after the audible result ended')

local_audio = DartsPresentationAudio.new
local = GameRoomDarts::Client.new(Object.new, DartsPresentationGame.new, clock: clock,
  audio: local_audio, mouse: DartsPresentationMouse.new)
capture_presentation_speech.call(local)
local.instance_variable_set(:@local_throw, {value: event['value'], impact_at: 3.0})
now = 2.0
local.event(event, before, after, 'Alice', DartsPresentationRepository.new)
assert(local_audio.calls.empty?, 'the throwing player heard the release cue twice after server confirmation')
now = 2.99
local.frame
assert(local_audio.calls.empty?, 'local impact ignored the release-time deadline')
now = 3.0
local.frame
assert(local_audio.calls.last == [:impact, score, 300, 0], 'local confirmed throw lost its delayed impact')

darts_presentation_speech.clear
next_audio = DartsPresentationAudio.new
next_client = GameRoomDarts::Client.new(Object.new, DartsPresentationGame.new, clock: clock,
  audio: next_audio, mouse: DartsPresentationMouse.new)
capture_presentation_speech.call(next_client)
next_before = DartsPresentationReplay.new(false, nil, %w[Alice Bob], {throw_index: 0}, 'Alice')
next_after = DartsPresentationReplay.new(false, nil, %w[Alice Bob],
  {throw_index: 1, dart: 2, round: 8, options: {'mode'=>'training'}}, 'Bob')
now = 4.0
next_client.event(event, next_before, next_after, 'Bob', DartsPresentationRepository.new)
now = 4.90
next_client.frame
now = 5.21
next_client.frame
assert(darts_presentation_speech.empty?, 'next-stage speech started with the score-quality cue')
now = 5.61
next_client.frame
assert(darts_presentation_speech.map(&:first) == ['Hit', "Alice scores #{score} points.", 'Round 8 throw 2'],
  'the next throw and round did not follow the score as one concise presentation')

darts_presentation_speech.clear
miss_audio = DartsPresentationAudio.new
miss_client = GameRoomDarts::Client.new(Object.new, DartsPresentationGame.new, clock: clock,
  audio: miss_audio, mouse: DartsPresentationMouse.new)
capture_presentation_speech.call(miss_client)
miss_event = {'__id' => 2, 'action' => 'darts_throw', 'value' => '0:1000:1000:500:m'}
miss_before = DartsPresentationReplay.new(false, nil, ['Alice'],
  {throw_index: 0, options: {'mode'=>'training'}}, 'Alice')
miss_after = DartsPresentationReplay.new(false, nil, ['Alice'],
  {throw_index: 1, dart: 2, round: 1, options: {'mode'=>'training'}}, 'Alice')
now = 6.0
miss_client.event(miss_event, miss_before, miss_after, 'Alice', DartsPresentationRepository.new)
now = 6.90
miss_client.frame
now = 7.21
miss_client.frame
assert(darts_presentation_speech.empty?, 'miss speech interrupted its impact and quality cues')
now = 7.61
miss_client.frame
assert(darts_presentation_speech.map(&:first).first == 'Miss',
  'training did not announce a miss before its score and next-throw prompt')

client.close
local.close
next_client.close
miss_client.close
puts 'PASS Darts presentation: release, impact lead, quality cue, training hit/miss speech and finished-view boundary'
