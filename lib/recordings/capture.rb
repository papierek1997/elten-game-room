require_relative 'document'
require_relative '../game_room_background'
require 'fileutils'

module GameRoomRecordings
  class Capture
    BATCH = 64
    QUEUE_LIMIT = 2048
    FRAME_INTERVAL = 0.04
    attr_reader :error

    # Chunks are immutable once published. An export leases the paths and a
    # copy of the pending suffix, never races an append to a half-written file.
    Snapshot = Struct.new(:header,:paths,:tail,:error,:owner,:lock,keyword_init:true) do
      def document
        capture=lock.synchronize { value,self.owner=owner,nil; value }
        raise Unavailable,'The recording export has already finished' unless capture
        raise Unavailable,error.message if error
        rows=[]
        paths.each do |path|
          raise Invalid,'Unsafe recording chunk' unless File.file?(path) && !File.symlink?(path)
          File.foreach(path) do |line|
            raise Invalid,'Recording chunk is too large' if line.bytesize>65_536 || rows.size>=Document::MAX_EVENTS
            rows << JSON.parse(line,max_nesting:16)
          end
        end
        Document.validate(Document.copy(header).merge('timeline'=>rows+Document.copy(tail)))
      rescue JSON::ParserError
        raise Invalid,'The recording is damaged or unsupported'
      ensure
        capture&.release_snapshot
      end
      def close
        capture=lock.synchronize { value,self.owner=owner,nil; value }
        capture&.release_snapshot
      end
    end

    def initialize(program:, metadata:, clock:, context:, work:nil)
      @program,@meta,@clock,@context=program,Document.copy(metadata),clock,context
      @started=@clock.call
      @lock=Mutex.new
      @work=work || GameRoomBackground::Work.new(runtime:program.class.app_runtime)
      @paths,@queue,@batch=[],[],nil
      @bytes=@count=@last_t=@generation=0
      @leases=0
      @last_frame_at=-Float::INFINITY
      program.manage(self) if program.respond_to?(:manage)
    end

    def frame(snapshot,paused:,force:false)
      return unless snapshot && !@closed && !@error
      now=@clock.call
      effects=snapshot['fx']&.last&.first
      important=force || effects!=@last_effect || paused!=@last_paused
      return if !important && now-@last_frame_at<FRAME_INTERVAL
      @last_frame_at,@last_effect,@last_paused=now,effects,paused
      data=Document.copy(@context.call)
      data.merge!('snapshot'=>snapshot,'paused'=>paused,'generation'=>@generation)
      add('frame',data)
    end

    def audio(method,args,kwargs)
      return if @closed || @error
      if method=='start_match'
        return if @match_start_recorded
        @match_start_recorded=true
      end
      kwargs=Document.copy(kwargs)
      kwargs['goal_at']=[kwargs['goal_at']-@started,0.0].max if kwargs['goal_at'].is_a?(Numeric)
      @generation+=1 if method=='reset'
      if method=='point' && kwargs['finished']==true
        @meta['complete_end']=true
        @finished_at=@clock.call
      end
      add('audio',{'method'=>method,'args'=>args,'kwargs'=>kwargs})
    end

    def pump
      @program.pump_recording_cleanup if @program.respond_to?(:pump_recording_cleanup)
      return if @closed
      if (outcome=@work.take)
        path,problem=outcome
        @lock.synchronize do
          @paths << path if path && !problem
          @error=problem if problem
          @batch=nil
        end
      end
      @last_t=[elapsed_ms,@last_t].max unless @finished_at && @clock.call>@finished_at+10
      return if @error || @work.busy?
      batch,index=nil,nil
      @lock.synchronize do
        if @queue.size>=BATCH
          batch,@queue=@queue,[]
          @batch=batch
          index=@paths.size
        end
      end
      return unless batch
      @work.start do
        allowed=@lock.synchronize { @writing=true unless @closed }
        if allowed
          directory=cache_directory
          FileUtils.mkdir_p(directory)
          raise Invalid,'Unsafe recording cache' if File.lstat(directory).symlink?
          prune_stale_cache unless @pruned_cache
          @pruned_cache=true
          path=File.join(directory,"chunk-#{index}.jsonl")
          File.open(path,File::WRONLY|File::CREAT|File::EXCL|File::BINARY,0o600) do |file|
            batch.each { |row| file.write(JSON.generate(row)+"\n") }
          end
          path
        end
      ensure
        @lock.synchronize { @writing=false }
        request_cleanup
      end
    rescue StandardError => problem
      @error=problem
      Log.warning("Power Games recording failed: #{problem.class}: #{problem.message}") if defined?(Log)
      nil
    end

    def snapshot
      pump
      @lock.synchronize do
        @leases+=1
        meta=Document.copy(@meta).merge('duration_ms'=>@last_t)
        if @finished_at
          meta['duration_ms']=[[@last_t,((@finished_at-@started)*1000).round+10_000].max,Document::MAX_DURATION].min
        end
        Snapshot.new(header:Document.header(meta),paths:@paths.dup.freeze,
          tail:Document.copy(Array(@batch)+@queue),error:@error,owner:self,lock:Mutex.new)
      end
    end

    def close
      @lock.synchronize { @closed=true }
      @work.close
      request_cleanup
      @program.release(self) if @program.respond_to?(:release)
    end

    def release_snapshot
      @lock.synchronize { @leases-=1 }
      request_cleanup
    end

    # Called only by the program's finite background cleanup task. Snapshot
    # leases and a running writer must have finished before this is queued.
    def cleanup_cache
      directory=cache_directory
      return unless File.directory?(directory)
      raise Invalid,'Unsafe recording cache' if File.lstat(directory).symlink?
      Dir.children(directory).each do |name|
        raise Invalid,'Unexpected recording cache file' unless /\Achunk-\d+\.jsonl\z/.match?(name)
        path=File.join(directory,name)
        stat=File.lstat(path)
        raise Invalid,'Unsafe recording chunk' unless stat.file? && !stat.symlink? && stat.nlink==1
        File.delete(path)
      end
      Dir.rmdir(directory)
    end

    private

    def cache_directory
      root=File.expand_path(@program.cache_path('recordings'))
      path=File.expand_path(File.join(root,@meta.fetch('id')))
      raise Invalid,'Unsafe recording cache' unless Document::UUID.match?(@meta['id']) && File.dirname(path)==root
      path
    end

    def request_cleanup
      ready=@lock.synchronize do
        if @closed && @leases.zero? && !@writing && !@cleanup_requested
          @cleanup_requested=true
        end
      end
      @program.schedule_recording_cache_cleanup(self) if ready && @program.respond_to?(:schedule_recording_cache_cleanup)
    end

    # A crashed/unloaded runtime can no longer drain its cleanup queue. Reap
    # only old, recognisable cache chunks; never library files or active writers.
    def prune_stale_cache
      root=File.dirname(cache_directory)
      raise Invalid,'Unsafe recording cache root' if File.lstat(root).symlink?
      Dir.children(root).each do |name|
        next if name==@meta['id'] || !Document::UUID.match?(name)
        directory=File.join(root,name)
        stat=File.lstat(directory)
        next unless stat.directory? && !stat.symlink? && stat.mtime<Time.now-1800
        entries=Dir.children(directory)
        next unless entries.all? { |entry| /\Achunk-\d+\.jsonl\z/.match?(entry) &&
          (item=File.lstat(File.join(directory,entry))).file? && !item.symlink? && item.nlink==1 }
        entries.each { |entry| File.delete(File.join(directory,entry)) }
        Dir.rmdir(directory)
      end
    end

    def elapsed_ms; [[((@clock.call-@started)*1000).round,0].max,Document::MAX_DURATION].min; end
    def add(kind,data)
      row={'t'=>elapsed_ms,'kind'=>kind,'data'=>Document.copy(data)}
      @lock.synchronize do
        @last_t=row['t']
        @queue << row
        @bytes+=JSON.generate(row).bytesize+2
        @count+=1
        if @queue.size>QUEUE_LIMIT || @count>Document::MAX_EVENTS || @bytes>Document::MAX_BYTES-65_536
          @error=Unavailable.new('The recording exceeded its safe size limit')
        end
      end
      pump
    rescue StandardError => problem
      @error=problem
      nil
    end
  end

  # Only the presentation calls are observed. Physics, keys, network packets,
  # result publication and the original renderer remain in their current owner.
  class AudioTap
    def initialize(audio,client)
      @audio,@client=audio,client
    end

    def update(snapshot,viewer:,paused:false)
      observe { |capture| capture.frame(snapshot,paused:paused) }
      @audio.update(snapshot,viewer:viewer,paused:paused)
    end

    def feedback(snapshot,viewer:,paused:)
      observe { |capture| capture.frame(snapshot,paused:paused,force:true) }
      @audio.feedback(snapshot,viewer:viewer,paused:paused)
    end

    def tick
      observe(&:pump)
      @audio.tick
    end

    Document::AUDIO_METHODS.each do |method|
      define_method(method) do |*args,**kwargs,&block|
        observe { |capture| capture.audio(method,args,kwargs) }
        @audio.public_send(method,*args,**kwargs,&block)
      end
    end

    def method_missing(method,*args,**kwargs,&block)
      @audio.public_send(method,*args,**kwargs,&block)
    end
    def respond_to_missing?(method,include_private=false); @audio.respond_to?(method,include_private); end
    def respond_to?(method,include_private=false)
      return @audio.respond_to?(method,include_private) if Document::AUDIO_METHODS.include?(method.to_s) || %i[feedback tick update].include?(method)
      super
    end

    private

    def observe
      return if @recording_failed
      capture=@client.recording
      yield capture if capture
    rescue StandardError=>error
      @recording_failed=true
      Log.warning("Power Games recording observer stopped: #{error.class}: #{error.message}") if defined?(Log)
    end
  end

  module CaptureClient
    def attach_recording
      return if @single_point || !@program.respond_to?(:create_game_recording) || !@game.recording_audio_kind
      @audio=AudioTap.new(@audio,self) unless @audio.is_a?(AudioTap)
    end

    def recording
      return @recording if @recording
      return if @recording_unavailable
      return unless @replay && @players && @program.respond_to?(:create_game_recording) && !@single_point
      @recording=@program.create_game_recording(@game,players:@players,options:@replay.state[:options],
        viewer:@viewer,complete_start:@replay.state[:rally].to_i.zero?,clock:@clock,context:method(:recording_context))
    rescue StandardError=>error
      @recording_unavailable=true
      Log.warning("Power Games recording unavailable: #{error.class}: #{error.message}") if defined?(Log)
      nil
    end

    def recording_context
      state=@replay&.state || {}
      {'rally'=>state[:rally].to_i,'scores'=>state[:scores] || [0,0], 'sets'=>state[:sets] || [0,0],
        'set_number'=>state[:set_number] || 1,
        'players'=>@players.map { |player| GameRoomContent.utf8(GameRoomParticipants.display_name(player)) },
        'teams'=>@teams || [0,1]}
    end
  end
end
