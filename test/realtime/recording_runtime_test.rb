require_relative '../support/ui'
require_relative '../support/recordings'
require_relative '../../lib/recordings/runtime'

class RecordingRuntimeProgram < RecordingTest::Program
  include GameRoomRecordings::Runtime
  class Runtime < TestTaskRuntime
    def initialize
      super('recording-runtime-test')
      @manifest.define_singleton_method(:build_id) {'260'}
    end
  end
  def self.app_runtime; @runtime ||= Runtime.new; end
end
module Session
  def self.name; 'Alice'; end
end unless defined?(Session)

Dir.mktmpdir('pg-recording-runtime-') do |directory|
  program=RecordingRuntimeProgram.new(directory)
  raise 'Fixture incorrectly exposes class runtime as an instance method' if program.respond_to?(:app_runtime)
  game=Struct.new(:recording_audio_kind,:name).new('axel_pong','Axel Pong')
  capture=program.create_game_recording(game,players:%w[Alice Bob],options:{},viewer:'Alice',complete_start:true,
    clock:-> {0.0},context:-> {RecordingTest.context})
  capture.frame(RecordingTest.scene,paused:false)
  value=capture.snapshot.document
  raise 'Wrong runtime build in metadata' unless value['metadata']['build']=='260'
  capture.close
end
RecordingRuntimeProgram.app_runtime.close
puts 'PASS recorder composition: real class-only runtime contract, source manifest build and normal client metadata'
