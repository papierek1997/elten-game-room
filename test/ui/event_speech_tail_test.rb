require_relative '../../lib/game_event_presenter'
require_relative '../../games/base'
require File.join(ENV.fetch('ELTEN_HOST_SOURCE'), 'src/eapi/speech')

def assert(value, message); raise message unless value; end

module Programs
  def self.with_runtime(runtime); raise 'Wrong callback runtime' unless runtime == :tail_runtime; yield; end
end
class TailProgram
  def self.app_runtime; :tail_runtime; end
  def self.normalized_settings; @settings ||= {}; end
end
game = Class.new(GameRoomGames::Base) do
  def describe_event(*); ['Alice, 100, for the third time.', 'Sold!']; end
  def event_speech_tail_sound(**); 'auction_gavel'; end
end.new
program = TailProgram.new
output = GameRoomSoundOutput.new(program, audio_game: false, covered: -> { false })
repository = Object.new
def repository.event_id(event); event.fetch('id'); end
spoken, played = [], []
original_play = GameRoomSounds.method(:play)
GameRoomSounds.define_singleton_method(:play) { |owner, asset, **| played << [owner, asset] }
presenter = GameRoomEventPresenter.new(game: -> { game }, repository: -> { repository }, program: -> { program },
  viewer: -> { 'Alice' }, client: -> { nil }, surface_state: -> { {} }, clock: -> { 0.0 }, covered: -> { false },
  speech: ->(text) { spoken << text }, trace: ->(*) {}, history_changed: ->(*) {}, session_changed: -> {})
replay = GameRoomGames::Replay.new(players: %w[Alice Bob], state: {}, history: [], accepted_events: [])
event = {'id'=>1, 'action'=>'auction_closed', 'actor'=>'Alice'}
begin
  presenter.present_game_event(event, replay, replay, replay, nil)
  sequence = spoken.last
  assert(sequence.is_a?(EltenAPI::Speech::SpeechSequence), 'The speech tail did not use the native sequence')
  assert(sequence.to_s == "Alice, 100, for the third time.\nSold!", 'A closing description was lost')
  assert(played.empty?, 'Gavel played before the closing words')
  sequence.execute(sequence.indexes.first)
  assert(played.empty?, 'Gavel ran at the start of the words')
  sequence.execute(sequence.indexes.last)
  assert(played == [[program, 'auction_gavel']], 'The native end index did not play the gavel')
  sequence.execute(sequence.indexes.last)
  assert(played.length == 1, 'The final speech index duplicated the gavel')
  presenter.present_game_event(event, replay, replay, replay, nil)
  abandoned = spoken.last
  output.close
  abandoned.execute(abandoned.indexes.last)
  assert(played.length == 1, 'Leaving the game played an abandoned gavel')
  output = GameRoomSoundOutput.new(program, audio_game: false, covered: -> { false })
  presenter.present_game_event(event, replay, replay, replay, nil)
  stale = spoken.last
  presenter.instance_variable_set(:@presentation_session_id, 'new-game')
  stale.execute(stale.indexes.last)
  assert(played.length == 1, 'An old session sounded in a new game')
  # A missing speech index does not block another presentation or the model.
  presenter.present_game_event(event, replay, replay, replay, nil)
  assert(spoken.last.is_a?(EltenAPI::Speech::SpeechSequence), 'A missing index blocked later presentation')
  TailProgram.normalized_settings['background_table_speech'] = false
  presenter.instance_variable_set(:@covered, -> { true })
  before = spoken.length
  presenter.present_game_event(event, replay, replay, replay, nil)
  assert(spoken.length == before && played.length == 2, 'Speech and sound background policies were coupled')
  puts 'PASS native speech-tail cue: full ordered speech, final-index-only playback, one cue, session/leave guards, missing-index progress and independent background policies'
ensure
  output.close
  GameRoomSounds.define_singleton_method(:play, original_play)
end
