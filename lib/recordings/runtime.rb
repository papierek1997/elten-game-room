require_relative 'library'
require_relative 'capture'
require_relative 'player'
require_relative 'renderer'
require_relative 'ui'

module GameRoomRecordings
  module Runtime
    using GameRoomLocalization::Translations

    def recording_library
      account=Session.name.to_s.downcase
      if !@recording_library || @recording_library.account!=account
        @recording_library=Library.new(self,account:account,current_account:-> { Session.name })
      end
      @recording_library
    end

    def create_game_recording(game,players:,options:,viewer:,complete_start:,clock:,context:)
      return unless game.recording_audio_kind
      @latest_game_recording&.close
      @recording_account=Session.name.to_s.downcase
      names=players.map { |player| GameRoomContent.utf8(GameRoomParticipants.display_name(player)) }
      meta=Document.metadata(game:game.recording_audio_kind,game_name:GameRoomContent.utf8(game.name),
        players:names,options:options || {},build:self.class.app_runtime&.manifest&.build_id,seat:players.index { |name| name.casecmp?(viewer.to_s) },complete_start:complete_start)
      @latest_game_recording=Capture.new(program:self,metadata:meta,clock:clock,context:context)
    end

    def schedule_recording_cache_cleanup(capture)
      (@recording_cleanup_lock ||= Mutex.new).synchronize do
        (@recording_cleanup_queue ||= []) << capture
      end
    end

    def pump_recording_cleanup
      return unless @recording_cleanup_lock
      @recording_cleanup_work ||= GameRoomBackground::Work.new(runtime:self.class.app_runtime)
      if (outcome=@recording_cleanup_work.take) && outcome[1]
        Log.warning("Power Games recording cache cleanup failed: #{outcome[1].class}") if defined?(Log)
      end
      return if @recording_cleanup_work.busy?
      batch=@recording_cleanup_lock.synchronize { @recording_cleanup_queue.shift(16) }
      return if batch.empty?
      @recording_cleanup_work.start { batch.each(&:cleanup_cache) }
    end

    def save_audio_history(client)
      capture=client&.recording
      unless capture && @recording_account==Session.name.to_s.downcase
        alert(_("The recording is not available yet."))
        return false
      end
      snapshot=capture.snapshot
      name=recording_task(_("Saving replay")) { recording_library.save_document(snapshot.document) }
      return false unless name
      alert(_("The replay has been added to Histories and replays."))
      true
    ensure
      snapshot&.close
      pump_recording_cleanup
    end

    def show_saved_games
      loop do
        choice=select_saved_game_item([_("Histories and replays"),_("Games to resume")],_("Saved games"))
        return if choice.nil?
        choice.zero? ? show_recording_library : show_resumable_games
      end
    end

    def show_recording_library
      UI.new(self).library
    end

    def recording_task(title,&operation)
      run_network_task(title,ui: :none,&operation)
    rescue UserMessage=>error
      alert(GameRoomContent.utf8(error.message))
      nil
    rescue Invalid,Unavailable,JSON::ParserError,IOError,SystemCallError,EncodingError => error
      Log.warning("Power Games recording operation failed: #{error.class}: #{error.message}") if defined?(Log)
      alert(_("The history or replay could not be opened or saved. The existing files have not been removed."))
      nil
    end

    def recording_audio(metadata,clock:)
      if metadata['game']=='axel_pong'
        require_relative '../axel_pong/audio'
        audio=GameRoomPong::Audio.new(self,clock:clock)
        audio.load
        audio.prepare_players(metadata['players'].length)
        Renderer.new(audio)
      elsif metadata['game']=='audio_ball'
        require_relative '../audio_ball/audio'
        Renderer.new(GameRoomAudioBall::Audio.new(self,clock:clock))
      else
        raise Invalid,'Unsupported audio recording'
      end
    end
  end
end
