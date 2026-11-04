require_relative 'prepared'

module GameRoomRecordings
  # A virtual clock and a passive renderer, never a session, channel, engine,
  # game repository, bot or statistics publisher. Seeking only reads data.
  class Player
    SPEEDS=[0.5,0.75,1.0,1.25,1.5,2.0].freeze
    attr_reader :position,:speed,:seat,:playing,:document

    def initialize(document,renderer:,clock:-> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      prepared=document.is_a?(Prepared) ? document : Prepared.copy(document)
      @document=prepared.document
      @events=@document.fetch('timeline')
      @factory,@clock=renderer,clock
      @speed,@seat,@position=1.0,@document['metadata']['seat'] || 0,0
      @playing=false
      @frames,@points,@sets,@actions=prepared.frames,prepared.points,prepared.sets,prepared.actions
      @scene_changes=prepared.scene_changes
      @markers=prepared.markers
      @match_start_index=prepared.match_start_index
      seek(0)
    end

    def metadata; @document.fetch('metadata'); end
    def duration; metadata.fetch('duration_ms'); end
    def frame; @frame; end

    def play
      seek(0) if @position>=duration
      @playing=true
      @anchor=@clock.call
      @audio.resume_playback if @audio.respond_to?(:resume_playback)
      render_frame if @frame
      self
    end

    def pause
      tick if @playing
      @playing=false
      @audio.respond_to?(:pause_playback) ? @audio.pause_playback : silence
      self
    end

    def toggle; @playing ? pause : play; end

    def seek(milliseconds)
      target=[[milliseconds.to_i,0].max,duration].min
      @audio&.close
      @position=target
      @navigation_anchor=nil
      @playing=false if target>=duration
      @audio=@factory.call(-> { @position/1000.0 })
      @audio.playback_speed=@speed if @audio.respond_to?(:playback_speed=)
      index=@frames.bsearch_index { |i| @events[i]['t']>target }
      selected=index ? (index.positive? ? @frames[index-1] : nil) : @frames.last
      @frame=selected && Document.copy(@events[selected]['data'])
      index=@scene_changes.bsearch_index { |i| @events[i]['t']>target } || @scene_changes.size
      change=index.positive? ? @scene_changes[index-1] : nil
      @awaiting_frame=change && (!selected || change>selected)
      point=point_at(target)
      update_scores(@events[point]['data']) if @frame && point && (!selected || point>selected)
      @cursor=@events.bsearch_index { |event| event['t']>target } || @events.length
      # Position zero starts with the actual opening cues, not a seek past them.
      @cursor=0 if target.zero?
      @fx_floor=target.zero? ? 0 : @frame&.dig('snapshot','fx')&.last&.first.to_i
      @generation=@frame && @frame['generation']
      @audio.prepare_players(metadata['players'].size) if @audio.respond_to?(:prepare_players)
      restore_score_queue(target,point)
      @anchor=@clock.call
      render_frame(prime:true) if @frame
      self
    end

    def seek_by(milliseconds); seek(@position+milliseconds); end

    def navigate(kind,direction)
      target=navigation_target(kind,direction)
      return self unless target
      seek([target-1,0].max)
      @navigation_anchor={kind:kind,time:target}
      self
    end

    def navigable?(kind,direction)
      !navigation_target(kind,direction).nil?
    end

    def speed=(value)
      raise ArgumentError,'Unsupported replay speed' unless SPEEDS.include?(value)
      tick if @playing
      @speed=value
      anchor=@navigation_anchor
      seek(@position)
      @navigation_anchor=anchor
    end

    def seat=(value)
      raise ArgumentError,'Invalid replay perspective' unless value.is_a?(Integer) && value.between?(0,metadata['players'].size-1)
      @seat=value
      anchor=@navigation_anchor
      seek(@position)
      @navigation_anchor=anchor
    end

    def tick
      now=@clock.call
      if @playing
        target=[@position+((now-@anchor)*1000*@speed).round,duration].min
        @anchor=now
        while @cursor<@events.length && @events[@cursor]['t']<=target
          event=@events[@cursor]
          @position=event['t']
          apply(event)
          @audio.tick if @audio.respond_to?(:tick)
          @cursor+=1
        end
        @position=target
        render_frame if @frame
        @audio.tick if @audio.respond_to?(:tick)
        if @position>=duration
          @playing=false
          silence
        end
      end
      @position
    end

    def close
      @playing=false
      @audio&.close
      @audio=nil
    end

    private

    # A jump lands just before its cue. Playing the cue on the next UI tick
    # must not make Previous/Next select that same marker forever. Keep its
    # exact boundary for successive backward jumps; forward navigation catches
    # up with natural playback. An explicit seek starts a fresh navigation walk.
    def navigation_target(kind,direction)
      markers=@markers.fetch(kind)
      return nil if markers.size==1
      origin=@position
      if @navigation_anchor && @navigation_anchor[:kind]==kind
        boundary=@navigation_anchor[:time]
        following=markers.bsearch { |time| time>boundary }
        origin=boundary if @position>=boundary-1 && (direction<0 || !following || @position<following)
      end
      if direction>0
        markers.bsearch { |time| time>origin }
      else
        index=markers.bsearch_index { |time| time>=origin } || markers.size
        markers[index-1] if index>0
      end
    end

    def update_scores(data)
      @frame['scores']=Document.copy(data['args'][0])
      @frame['sets']=Document.copy(data['kwargs']['sets']) if data['kwargs']['sets']
    end

    def point_at(target)
      index=@points.bsearch_index { |i| @events[i]['t']>target } || @points.size
      @points[index-1] if index>0
    end

    def restore_score_queue(target,index)
      return unless @audio.respond_to?(:recording_seek)
      return unless index
      event=@events[index]
      return if target-event['t']>60_000
      keys=Document.copy(event['data']['kwargs']).transform_keys(&:to_sym)
      keys[:viewer]=team_viewer
      keys[:goal_at] ||= event['t']/1000.0
      @position=event['t']
      @audio.point(*Document.copy(event['data']['args']),**keys)
      @position=target
      @audio.recording_seek(target/1000.0)
      @audio.pause_playback if !@playing && @audio.respond_to?(:pause_playback)
    end

    def apply(event)
      if event['kind']=='frame'
        @frame=Document.copy(event['data'])
        @awaiting_frame=false
        if @generation!=@frame['generation']
          @generation=@frame['generation']
          @fx_floor=0
        end
        render_frame
      else
        data=event['data']; method=data['method']
        # Live audio ignores later start_match calls on the same renderer.
        # Seeking recreates that renderer, not the beginning of the match.
        return if method=='start_match' && @cursor!=@match_start_index
        return unless @audio.respond_to?(method)
        args=Document.copy(data['args'])
        keys=Document.copy(data['kwargs']).transform_keys(&:to_sym)
        keys[:viewer]=team_viewer if keys.key?(:viewer)
        if method=='point' && @frame
          update_scores(data)
        end
        # Keep scores for the controls, but never render the preceding flight
        # over a new goal, prepare/stop cue or reset while its frame is pending.
        @awaiting_frame=true if Document::SCENE_METHODS.include?(method)
        @audio.public_send(method,*args,**keys)
      end
    end

    def team_viewer
      (@frame && @frame['teams'] || (metadata['players'].size==4 ? [0,1,0,1] : [0,1]))[@seat]
    end
    def frame_viewer; metadata['game']=='audio_ball' ? team_viewer : @seat; end

    def render_frame(prime:false)
      return if @awaiting_frame

      state=Document.copy(@frame['snapshot'])
      state['fx']=state['fx'].reject { |fx| fx[0]<=@fx_floor } if state['fx']
      @audio.update(state,viewer:frame_viewer,paused:prime || !@playing || @frame['paused'])
    end

    def silence
      if @audio.respond_to?(:silence)
        @audio.silence
      elsif @audio.respond_to?(:suspend)
        @audio.suspend
      end
    end
  end
end
