require 'tmpdir'
require_relative '../../lib/recordings/library'
require_relative '../../lib/recordings/capture'
require_relative '../../lib/recordings/player'

module RecordingTest
  module_function
  def assert(value,message='Recording assertion failed'); raise message unless value; end
  def refuses(type=GameRoomRecordings::Invalid)
    yield
    raise 'Expected rejection'
  rescue type
    true
  end

  def scene
    {'tick'=>1,'p'=>[25.0,25.0],'b'=>{'x'=>25.0,'y'=>25.0,'dx'=>0.0,'dy'=>1.0},
      'fx'=>[],'shields'=>[0,0],'invisible'=>false,'server'=>0,'goal'=>nil,'edges'=>[0,0]}
  end
  def context
    {'rally'=>0,'scores'=>[0,0],'sets'=>[0,0],'set_number'=>1,'teams'=>[0,1],'players'=>%w[Alice Bob]}
  end
  def document
    meta=GameRoomRecordings::Document.metadata(game:'axel_pong',game_name:'Axel Pong',players:%w[Alice Bob],now:Time.at(1_800_000_000))
    meta['duration_ms']=5000
    frame=context.merge('snapshot'=>scene,'paused'=>false,'generation'=>0)
    GameRoomRecordings::Document.header(meta).merge('timeline'=>[
      {'t'=>0,'kind'=>'frame','data'=>frame},
      {'t'=>1000,'kind'=>'audio','data'=>{'method'=>'goal','args'=>[],'kwargs'=>{'viewer'=>0,'winner'=>1}}},
      {'t'=>1200,'kind'=>'audio','data'=>{'method'=>'point','args'=>[[0,1]],'kwargs'=>{'viewer'=>0,'winner'=>1,'finished'=>false,'goal_at'=>1.0}}},
      {'t'=>1400,'kind'=>'frame','data'=>frame.merge('scores'=>[0,1],'rally'=>1,'paused'=>true)}])
  end

  class Program
    def initialize(root); @root=root; end
    def data_path(path=''); File.join(@root,'data',path); end
    def cache_path(path=''); File.join(@root,'cache',path); end
    def manage(_); end
    def release(_); end
    def schedule_recording_cache_cleanup(capture); capture.cleanup_cache; end
  end
  class Work
    def start(&operation)
      raise 'Overlapping recording task' if @result
      @result=begin [operation.call,nil]; rescue StandardError=>error; [nil,error]; end
      true
    end
    def take; value=@result;@result=nil;value; end
    def busy?; !@result.nil?; end
    def close; @result=nil; end
  end
  class Audio
    attr_reader :events
    def initialize(events,clock);@events,@clock=events,clock;end
    %i[update reset start_match goal point prepare stop_ball announce announce_set hurry tick close silence prepare_players].each do |method|
      define_method(method) { |*args,**keys| @events << [method,@clock.call,args,keys] }
    end
  end
end
