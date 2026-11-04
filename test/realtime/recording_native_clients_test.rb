require_relative '../support/audio_ball_client'
require_relative '../support/recordings'

module RecordingClientFixture
  class << self; attr_accessor :root,:captures; end
end

class Program
  def cache_path(path=''); File.join(RecordingClientFixture.root,path); end
  def manage(_); end
  def release(_); end
  def schedule_recording_cache_cleanup(capture); capture.cleanup_cache; end
  def create_game_recording(game,players:,options:,viewer:,complete_start:,clock:,context:)
    metadata=GameRoomRecordings::Document.metadata(game:game.recording_audio_kind,game_name:game.name,
      players:players,options:options,seat:players.index(viewer),complete_start:complete_start)
    capture=GameRoomRecordings::Capture.new(program:self,metadata:metadata,clock:clock,context:context,work:RecordingTest::Work.new)
    RecordingClientFixture.captures << capture
    capture
  end
end

Dir.mktmpdir('pg-native-recordings-') do |directory|
  RecordingClientFixture.root=directory
  RecordingClientFixture.captures=[]
  [false,true].each do |doubles|
    players=doubles ? %w[Alice Bob Carol Dave] : %w[Alice Bob]
    pong=PongHarness.new(players:players,options:{'team_size'=>doubles ? 2 : 0})
    pong.press('Alice')
    pong.advance(500)
    pong.clients.each do |name,client|
      value=client.recording.snapshot.document
      raise "Missing Pong frames for #{name}" if value['timeline'].none? { |event| event['kind']=='frame' }
      raise 'Wrong Pong seat count' unless value['metadata']['players'].size==players.size
    end
    pong.close

    ball=AudioBallHarness.new(players:players,options:{'team_size'=>doubles ? 2 : 0})
    ball.advance_for(1)
    ball.press('Alice','up')
    ball.advance_for(8)
    ball.clients.each do |name,client|
      value=client.recording.snapshot.document
      raise "Missing Audio Ball frames for #{name}" if value['timeline'].none? { |event| event['kind']=='frame' }
    end
    ball.close
  end
  RecordingClientFixture.captures.each(&:close)
  raise 'Temporary recording chunks survived cleanup' unless Dir.glob(File.join(directory,'*','chunk-*.jsonl')).empty?
end
puts 'PASS production audio clients: captured real Pong and Audio Ball frames/events, singles/doubles and observers, schema validation and leased-cache cleanup'
