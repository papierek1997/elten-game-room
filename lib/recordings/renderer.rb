module GameRoomRecordings
  # Playback-only ownership of the existing game's sound handles. Pausing does
  # not cancel its queued score announcements or rewind the active recordings.
  class Renderer
    def initialize(audio)
      @audio=audio
      @paused=[]
    end

    def pause_playback
      @paused=@audio.recording_sound_handles.select(&:playing?)
      @paused.each(&:pause)
    end

    def resume_playback
      @paused.each { |sound| sound.play unless sound.closed? }
      @paused.clear
    end

    def playback_speed=(rate)
      return if rate==1.0
      @audio.recording_sound_handles.each { |sound| sound.tempo=(rate-1.0)*100.0 }
    end

    def close
      @paused.clear
      @audio.close
    end

    def method_missing(method,*args,**kwargs,&block)
      @audio.public_send(method,*args,**kwargs,&block)
    end
    def respond_to_missing?(method,include_private=false); @audio.respond_to?(method,include_private); end
  end
end
