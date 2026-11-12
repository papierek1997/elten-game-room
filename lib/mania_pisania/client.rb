# encoding: UTF-8
require_relative 'practice'
require_relative 'word_bank'
require_relative 'text_library'
require_relative 'braille'
require_relative 'settings'
require_relative 'error_feedback'
require_relative 'text_import_dialog'
require_relative 'text_library_dialog'
require_relative 'survival_music'
require_relative 'shared_text'
require_relative '../game_sounds'
require_relative '../game_room_ui'
require_relative '../hidden_submissions'
require_relative '../realtime/progress'
require 'securerandom'

module GameRoomTyping
  using GameRoomLocalization::Translations
  class Client
    using GameRoomLocalization::Translations

    def initialize(program, game, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, checkpoint_vault: nil, progress_factory: nil, **_services)
      @program, @game, @clock = program, game, clock
      @ui_thread = Thread.current
      @progress_factory = progress_factory || ->(**options, &block) { GameRoomRealtime::Progress.new(**options, &block) }
      @library = TextLibrary.new(program)
      @settings = Settings.new(program)
      @feedback = ErrorFeedback.new(program, @settings, speech: ->(text) { announce(text, stop: !@input_echo) })
      @round = nil
      @checkpoint_vault = checkpoint_vault
    end

    def _(source); GameRoomContent.utf8(super(source)); end

    def bind_screen(session_id:, table_id:, owner:, viewer:, members:)
      @viewer = viewer
      @session_id = session_id
      @table_id = table_id
    end

    def start
      return false if @closed
      @progress ||= @progress_factory.call(program: @program, clock: @clock,
        key: [:mania_pisania, @table_id, @session_id, @viewer]) { |background| frame(background: background) }
      true
    end
    def background_progress?; true; end
    def update_table_control(session)
      @restored_session = session['__event_id_base'].to_i > 0
    end
    def refresh_due?; false; end
    def action(_selection, _replay, _viewer); false; end
    def error(_status); end

    # GameScreen calls this for every durable event. It presents the canonical
    # history itself; local practice is synchronized in before_wait/after_events,
    # not here, so network events cannot reset a word or repeat its prompt.
    def event(_event, _before_replay, _after_replay, _viewer, _repository); end

    def automatic_error(status)
      if @save_action || @replay&.state&.[](:saving)
        @save_action = nil
        @save_requested = false
        @checkpoint_error = true
        @practice&.resume unless @replay&.state&.[](:saving)
        alert(@game.move_error(status))
        return
      end
      @shared_text_parts = nil if @replay&.state&.[](:phase) == :setup
      @result_error = true
      alert(@game.move_error(status))
    end

    def context_data
      return {'typing_save_action' => @save_action} if @save_action
      if @replay&.state&.[](:saving) && @practice&.paused? && @replay.players.length > 1 && !@result_confirmed && !@checkpoint_error
        checkpoint = @practice.snapshot
        # Reject an oversized atomic move here, not in GameScreen's planner.
        # This leaves the local pause intact and the host's cancel button usable.
        GameRoomActionPayload.commands(@game.id, {'action' => 'checkpoint', 'round' => @round,
          'save_id' => @replay.state[:saving][:id], 'checkpoint' => checkpoint})
        return {'typing_checkpoint' => checkpoint}
      end
      if @shared_text_parts && @replay&.state&.[](:phase) == :setup && @viewer.to_s.casecmp?(@replay.state[:owner].to_s)
        return {'typing_text_parts' => @shared_text_parts}
      end
      return {'typing_result' => @blocked_result} if @blocked_result && !@result_confirmed && !@result_error
      return {} unless @practice&.result && !@result_error && !@result_confirmed
      {'typing_result' => {'round' => @round, 'result' => @practice.result.dup}}
    rescue ArgumentError => exception
      @checkpoint_error = true
      alert(_('Could not prepare the typing save: %{reason}') % {reason: GameRoomContent.utf8(exception.message)})
      {}
    end

    def before_wait(replay, viewer)
      @viewer ||= viewer
      @replay = replay
      if @restored_session && !@restore_boundary_recorded
        @restore_round = replay.state[:round] if replay.state[:phase] == :active
        @restore_boundary_recorded = true
      end
      if @restored_session && replay.state[:saving] && @viewer.to_s.casecmp?(replay.state[:owner].to_s) && !@restore_resume_requested
        @restore_resume_requested = true
        queue_save_action('save_resume', replay.state[:saving][:id])
      end
      if replay.state[:phase] == :setup && SharedText.required?(replay.state[:options], replay.players, owner: replay.state[:owner]) && !replay.state[:shared_text]
        identity = [replay.state[:round], replay.state[:owner]]
        if !covered? && viewer.casecmp?(replay.state[:owner]) && @shared_text_prompted != identity
          @shared_text_prompted = identity
          choose_shared_text
        end
        return
      end
      @result_confirmed = replay.state[:results].keys.any? { |name| name.casecmp?(viewer) }
      synchronize_save_pause
      return unless replay.state[:phase] == :active && !@result_confirmed && replay.players.any? { |name| name.casecmp?(viewer) }
      if @round == replay.state[:round]
        synchronize_save_pause
        return
      end

      # Picking/pasting a private text belongs to the visible game, never to
      # the active UI bridge while the player is reading Messages or the forum.
      options = replay.state[:options]
      unless @word_bank&.language == options.fetch('word_language', 'pl')
        @word_bank = WordBank.for_options(options)
      end
      return if covered? && options['variant'] == 'free' && %w[local pasted].include?(options['text']) &&
        !replay.state[:shared_text] && !(@restored_session && @restore_round == replay.state[:round])

      start_round(replay, viewer, options)
    rescue TextSelection::Unavailable
      block_round
      alert(_('The selected text is no longer available on this computer. Choose it again in the table settings before starting.'))
    rescue BrailleUnavailable, Fiddle::DLError => exception
      block_braille_round(exception)
    rescue IOError => exception
      block_music_round(exception)
    end

    private def start_round(replay, viewer, options)
      save_progress
      @music&.close
      @music = nil
      @reset_progress_round = nil
      @blocked_result = nil
      @practice = nil
      text_id = "builtin:#{options['text']}"
      shared = replay.state[:shared_text]
      restoring = @restored_session && @restore_round == replay.state[:round] && !@restored_round_loaded
      @restored_private_data = nil unless restoring
      restored = restored_checkpoint(replay, viewer) if restoring
      private_source = @restored_private_data && @restored_private_data['source']
      private_source = private_source.merge('id' => @restored_private_data['text_id']) if private_source
      shared ||= private_source
      @shared_text_parts = nil if shared
      selected = TextSelection.resolve(options, @library) if !shared && TextSelection.descriptor(options)
      if selected
        shared = selected
      elsif !shared && options['variant'] == 'free' && TextSelection.descriptor(options)
        raise TextSelection::Unavailable
      else
        # Compatibility with tables created before text selection moved to
        # table creation. Newly prepared tables never reopen a source picker.
        text_id = choose_text if !shared && options['variant'] == 'free' && options['text'] == 'local'
        text_id = TextImportDialog.new(@program, @library, paste_only: true).wait if !shared && options['variant'] == 'free' && options['text'] == 'pasted'
      end
      text_id = shared['id'] if shared
      text = shared || @library.fetch(text_id)
      if options['variant'] == 'free' && options['text'] != 'own' && !text
        # Cancelling local selection leaves a real, explicit empty result.
        text_id = 'builtin:apple_tree'
        text = @library.fetch(text_id)
        cancelled = true
      end
      @translator = LibLouis.discover(program: @program) if options['input'] != 'keyboard'
      progress = replay.players.length == 1 ? @library.progress_for(text_id).slice('position') : {}
      if text && progress['position'].to_i >= Document.new(text['text']).tokens.length
        progress = {}
      end
      @round = replay.state[:round]
      @focus_round = @round
      @result_error = @result_confirmed = false
      if options['variant'] == 'survival'
        @music = SurvivalMusic.new(@program, difficulty: options.fetch('difficulty', 'easy'), settings: @settings)
      end
      @practice = Practice.new(options: options, word_bank: @word_bank, seed: replay.state[:seed],
        multiplayer: replay.players.length > 1, text: text && text['text'], text_id: text_id,
        progress: progress, translator: @translator, table: restored && restored['table'] != 'custom' ? restored['table'] : @settings['braille_table'], clock: @clock,
        recording_seconds: @music&.duration)
      @source_item = text && {'title' => text['title'], 'text' => text['text']}
      restored ? @practice.restore(restored) : @practice.start
      @restored_round_loaded = true if restoring
      @practice.finish if cancelled
      synchronize_save_pause
    end

    def after_events(replay, viewer, context:)
      before_wait(replay, viewer)
      save_progress if @practice&.finished?
    end

    def attach_view(form, surface)
      detach_view
      return unless surface.is_a?(GameSurfaces::TypingSurface)
      @ui_thread = Thread.current
      @form, @surface = form, surface
      surface.on_character = method(:input)
      surface.on_command = method(:command)
      start unless @progress
      @progress.attach(form)
      present unless covered?
    end

    def detach_view
      @progress&.detach
      if @surface
        @surface.on_character = nil
        @surface.on_command = nil
      end
      @form = @surface = nil
    end

    def tick
      @progress ? @progress.update : frame
    end

    def frame(background: false)
      return if @presenting || @closed || !@practice
      @background_frame = background
      complete_prompt unless speech_pending?
      @practice.tick
      present(background: background)
    rescue BrailleUnavailable, Fiddle::DLError => exception
      block_braille_round(exception)
    rescue IOError => exception
      block_music_round(exception)
    ensure
      @background_frame = false
    end

    def input(character)
      return if !@practice || @practice.paused? || @practice.finished? || @result_confirmed || @presenting
      return if @practice.braille? && !SixKeyChord.input?(character)
      @input_echo = echo_input(character)
      complete_prompt # A fresh key intentionally interrupts the word prompt.
      @practice.input(character)
      present
    rescue BrailleUnavailable, Fiddle::DLError => exception
      # A custom table can reject a later word. Retire this practice result,
      # not the entire native UI loop.
      block_braille_round(exception)
    rescue IOError => exception
      block_music_round(exception)
    ensure
      @input_echo = false
    end

    def command(command)
      if command == 'typing_choose_text'
        return choose_shared_text if @replay&.state&.[](:phase) == :setup && @viewer.to_s.casecmp?(@replay.state[:owner].to_s)
        return
      end
      return unless @practice && !@practice.paused?
      case command
      when 'typing_spell' then present_help { @practice.spell }
      when 'typing_repeat' then present_help { @practice.repeat }
      when 'typing_word_rest' then present_help { @practice.remaining_word }
      when 'typing_sentence' then present_help { @practice.remaining_sentence }
      when 'typing_status'
        speak(_('Words: %{words}. Errors: %{errors}. WPM: %{wpm}.') % {
          words: @practice.engine.correct_words, errors: @practice.errors, wpm: @practice.engine.wpm})
      when 'typing_finish'
        @practice.finish
        save_progress
        present
      end
    rescue BrailleUnavailable, Fiddle::DLError => exception
      block_braille_round(exception)
    end

    def pending_screen_action(replay)
      if @save_requested && !@save_dialog_running && @game.save_ready?(replay)
        @save_dialog_running = true
        :save_game
      end
    end

    def prepare_save(replay, context:)
      return true if replay.state[:phase] == :between
      unless replay.state[:phase] == :active
        alert(_('Start typing before saving the game.'))
        return false
      end
      return true if @save_requested && @game.save_ready?(replay)
      return false if @save_requested
      return false unless @viewer.to_s.casecmp?(replay.state[:owner].to_s)
      if replay.players.length == 1 && !@viewer.to_s.casecmp?(replay.players.first)
        alert(_('Only the solo player can save their private typing progress.'))
        return false
      end
      options = replay.state[:options]
      if replay.players.length == 1 && options['variant'] == 'free' && %w[local pasted].include?(options['text']) && @source_item
        return false unless confirm(_('Save this solo game on your Elten account? The text "%{title}" will be included in a private archive.') % {title: @source_item['title']})
      end
      @practice&.pause
      @music&.stop
      if replay.players.length == 1
        raise ArgumentError, _('Typing has not started.') unless @practice
        @checkpoint_vault ||= context.hidden_submissions
        @checkpoint_vault.prepare(session_id: context.session_id, round_id: "mania-save:#{replay.state[:round]}",
          user: @viewer, payload: {'format' => 1, 'checkpoint' => @practice.snapshot, 'source' => @source_item, 'text_id' => @practice.text_id})
      end
      @save_requested = true
      @checkpoint_error = false
      queue_save_action('save_begin', SecureRandom.hex(16))
      false
    rescue ArgumentError, HiddenSubmissions::StorageError => exception
      @practice&.resume
      alert(_('Could not prepare the typing save: %{reason}') % {reason: GameRoomContent.utf8(exception.message)})
      false
    end

    def save_finished(success)
      @save_dialog_running = false
      return if success
      @save_requested = false
      saving = @replay&.state&.[](:saving)
      queue_save_action('save_cancel', saving[:id]) if saving
    end

    def show_settings
      texts = Button.new(_('Local texts and progress'))
      labels = BrailleCatalog.labels
      tables = BrailleCatalog::FILES.keys.select { |id| BrailleCatalog.visible?(id) }.map { |id| [id, labels.fetch(id)] }
      current_table = @settings['braille_table']
      unless BrailleCatalog::FILES.key?(current_table)
        tables << [current_table, _('Local Liblouis table') + ': ' + File.basename(current_table)]
      end
      tables << [nil, _('Local Liblouis table')]
      table = ListBox.new(tables.map { |_id, label| GameRoomContent.utf8(label) }, header: _('Braille table'),
        index: tables.index { |id, _label| id == current_table } || 0, quiet: true)
      speech = CheckBox.new(_('Announce typing errors with speech'), checked: @settings['error_speech'])
      sounds = CheckBox.new(_('Announce typing errors with sounds'), checked: @settings['error_sounds'])
      # Native Elten settings use descending percentage lists: Up increases
      # the value, Down decreases it, one percent per item.
      volume = ListBox.new(100.downto(0).map { |number| "#{number}%" },
        header: _('Music volume'), index: 100 - @settings['music_volume'], quiet: true)
      echo = ListBox.new([_('Use Elten setting'), _('None'), _('Characters'), _('Words'), _('Characters and words')],
        header: _('Typing echo during the game'), index: Settings::ECHO_MODES.index(@settings['typing_echo']), quiet: true)
      save, cancel = Button.new(_('Save')), Button.new(_('Cancel'))
      form = GameRoomUI::Form.new([table, speech, sounds, volume, echo, texts, save, cancel], program: @program, quiet: true)
      form.accept_button, form.cancel_button = save, cancel
      texts.on(:press) { choose_text(select: false); texts.focus }
      save.on(:press) do
        translator = nil
        begin
          value = tables.fetch(table.index).first || choose_local_braille_table
          unless value
            form.index = 0
            table.focus
            next
          end
          table_changed = value != @settings['braille_table']
          if table_changed
            translator = LibLouis.discover(program: @program)
            translator.table_path(value)
          end
          @settings.save('braille_table' => value, 'error_speech' => speech.checked, 'error_sounds' => sounds.checked,
            'music_volume' => 100 - volume.index, 'typing_echo' => Settings::ECHO_MODES.fetch(echo.index))
          @practice&.select_braille_table(value) if table_changed
          @music&.update_volume
          form.resume
        rescue BrailleUnavailable, Fiddle::DLError => exception
          alert(_('Braille is unavailable: %{reason}') % {reason: GameRoomContent.utf8(exception.message)})
        rescue IOError, SystemCallError
          alert(_('Could not save typing settings.'))
        ensure
          translator&.close
        end
      end
      cancel.on(:press) { form.resume }
      form.wait
    end

    def close
      @closed = true
      @progress&.close
      @progress = nil
      detach_view
      @music&.close
      @music = nil
      save_progress
    end

    private

    def queue_save_action(action, save_id)
      @save_action = {'action' => action, 'save_id' => save_id,
        'round' => @replay.state[:round], 'owner' => @viewer}
    end

    def covered?
      @background_frame || GameRoomBackgroundPolicy.covered?(@ui_thread, program: @program, form: @form)
    end

    def announce(text, stop: true)
      background = covered?
      return false unless GameRoomBackgroundPolicy.speech?(@program, covered: background)
      background ? speak(text, stop: false, break_sequence: false) : speak(text, stop: stop)
      true
    end

    def echo_input(character)
      mode = @settings.typing_echo
      text = if character == ' '
        @practice.buffer if %w[words characters_and_words].include?(mode)
      elsif %w[characters characters_and_words].include?(mode)
        character == "\b" ? (@practice.buffer[-1] if @practice.free?) : character
      end
      text = if text.to_s.empty?
        # A rejected cell never enters the word stream's buffer. Even word-only
        # echo must identify its points at the failed key, before it is lost.
        @practice.undefined_braille_echo(character) if mode == 'words'
      else
        @practice.echo_text(text, character: character)
      end
      return false if text.to_s.empty?
      # Speak now, before input can generate a new word prompt. Queue behind
      # an outstanding prompt, without blocking typing or the active UI clock.
      announce(GameRoomContent.utf8(text), stop: !prompt_speech_pending?)
    end

    def prompt_speech_pending?
      @prompt_speech_deadline && @clock.call < @prompt_speech_deadline &&
        respond_to?(:speech_actived, true) && speech_actived
    end

    def speech_pending?
      @pending_prompt && @clock.call < @pending_prompt[:deadline] &&
        respond_to?(:speech_actived, true) && speech_actived
    end

    def complete_prompt
      pending, @pending_prompt = @pending_prompt, nil
      return unless pending && pending[:practice].equal?(@practice) && !@practice.paused? && !@practice.finished?
      @music&.start(rate: @practice.engine.playback_rate, position: @practice.engine.playback_position)
      @practice.prompt_finished
    end

    def checkpoint_vault
      @checkpoint_vault ||= HiddenSubmissions::Vault.new(HiddenSubmissions::ProgramStorage.new(@program))
    end

    def restored_checkpoint(replay, viewer)
      return nil unless replay.state[:phase] == :active
      if replay.players.length == 1
        @restored_private_data = checkpoint_vault.reveal(session_id: @session_id,
          round_id: "mania-save:#{replay.state[:round]}", user: viewer)&.payload
        raise ArgumentError, _('The restored private typing progress is unavailable.') unless @restored_private_data
        @restored_private_data['checkpoint']
      else
        saved = replay.state[:saving]&.[](:checkpoints) || replay.state[:resume_checkpoints] || {}
        saved.find { |name, _checkpoint| name.casecmp?(viewer) }&.last
      end
    end

    def synchronize_save_pause
      return unless @replay
      saving = @replay.state[:saving]
      @save_action = nil if saving && @save_action && @save_action['action'] == 'save_begin' && @save_action['save_id'] == saving[:id]
      if !saving && @save_action && %w[save_cancel save_resume].include?(@save_action['action'])
        @save_action = nil
      end
      @save_requested = false unless saving || (@save_action && @save_action['action'] == 'save_begin')
      @checkpoint_error = false unless saving
      return unless @practice
      if saving
        @practice.pause
        @music&.stop
      elsif @save_action && @save_action['action'] == 'save_begin'
        # Keep the requesting player paused until the request is acknowledged.
      else
        if @save_action && %w[save_cancel save_resume].include?(@save_action['action'])
          @save_action = nil
        end
        @save_requested = false
        @practice.resume if @practice.paused?
      end
    end

    def choose_shared_text
      return unless SharedText.required?(@replay.state[:options], @replay.players, owner: @replay.state[:owner])
      options = @replay.state[:options]
      if TextSelection.descriptor(options)
        item = TextSelection.resolve(options, @library)
        unless item
          alert(_('The selected text is no longer available on this computer. Choose it again in the table settings before starting.'))
          return
        end
      else
        id = if options['text'] == 'pasted'
          TextImportDialog.new(@program, @library, paste_only: true).wait
        else
          choose_text
        end
        item = id && @library.fetch(id)
      end
      return unless item
      if item['text'].bytesize > SharedText::MAX_BYTES
        alert(_('Maximum text size: %{bytes} UTF-8 bytes (1000 kB).') % {bytes: SharedText::MAX_BYTES})
        return
      end
      @shared_text_parts = SharedText.parts(item)
    end

    def present_help
      @presenting = true
      @practice.help_started
      speak(GameRoomContent.utf8(yield.to_s))
      speech_wait
    ensure
      @practice.help_finished
      @presenting = false
    end

    def present(background: false)
      return unless @practice
      @presenting = true
      notices = @practice.take_notices
      @music&.stop if @practice.finished? || @practice.paused? || notices.any? { |kind, _text| kind == :prompt }
      error_spoken = false
      notices.each do |kind, text, count|
        if kind == :error
          @feedback.present(GameRoomContent.utf8(text), count: count, free: @practice.free?)
          error_spoken = @settings['error_speech']
        else
          # The next word must not cancel the just-announced mistake. Native
          # stop:false queues it behind that message without blocking per-key UI.
          announced = announce(GameRoomContent.utf8(text), stop: !(error_spoken || @input_echo || prompt_speech_pending?))
          error_spoken = false
        end
        if kind == :prompt
          # Observe speech completion on the existing active-UI clock. Never
          # enter speech_wait from a timer/background bridge or per-word input.
          @pending_prompt = {practice: @practice, deadline: @clock.call + 30.0}
          @prompt_speech_deadline = @pending_prompt[:deadline] if announced
          complete_prompt unless announced && speech_pending?
        end
      end
      @music&.update_volume
      if @practice.finished? && !@completed_practice.equal?(@practice)
        @completed_practice = @practice
        @music&.close
        @music = nil
        GameRoomSounds.play(@program, 'typing_endgame')
      end
      @surface&.present(buffer: @practice.display_buffer, braille: @practice.braille?) unless background || covered?
      if @focus_round && !background && !covered? && @focus_round == @round && @surface&.spec&.enabled && @surface.spec.round == @round
        target = @surface.fields.first
        index = @form&.fields&.index(target)
        if index
          @form.index = index unless @form.index == index
          @focus_round = nil
        end
      end
    rescue IOError => exception
      block_music_round(exception)
    ensure
      @presenting = false
    end

    def save_progress
      return unless @practice&.free? && @practice.engine.respond_to?(:snapshot) && @replay && @replay.players.length == 1
      return if @reset_progress_round == [@round, @practice.text_id]
      snapshot = @practice.engine.snapshot
      identity = [@practice.text_id, snapshot]
      return if @last_progress == identity
      @library.save_progress(@practice.text_id, snapshot)
      @last_progress = identity
    rescue IOError, SystemCallError => exception
      unless @progress_error_shown
        @progress_error_shown = true
        alert(_('Could not save typing progress: %{reason}') % {reason: exception.message})
      end
    end

    def block_braille_round(exception)
      block_round
      alert(_('Braille is unavailable: %{reason}') % {reason: GameRoomContent.utf8(exception.message)})
    end

    def block_music_round(exception)
      block_round
      alert(_('Survival music is unavailable: %{reason}') % {reason: GameRoomContent.utf8(exception.message)})
    end

    def block_round
      @music&.close
      @music = nil
      @round = @replay.state[:round]
      @practice = nil
      @blocked_result = {'round' => @round, 'result' => {'words' => 0, 'errors' => 5, 'levels' => 0, 'elapsed_ms' => 0, 'wpm' => 0.0, 'assisted' => true}}
    end

    def choose_text(select: true)
      reset = lambda do |id|
        @reset_progress_round = [@round, id] if @practice&.text_id == id
        @last_progress = nil
      end
      TextLibraryDialog.new(@program, @library, on_reset: reset,
        alert: ->(text) { alert(text) }, confirm: ->(text) { confirm(text) }).wait(select: select)
    end

    def choose_local_braille_table
      label = _('Choose a Liblouis table: .ctb, .utb, .tbl or .uti.')
      alert(label)
      root = 'C:/Program Files/NVDA/louis/tables/'
      root = '' unless File.directory?(root)
      tree = FilesTree.new(label, path: root, extensions: LibLouis::TABLE_EXTENSIONS, quiet: true)
      accept, cancel = Button.new(_('Open')), Button.new(_('Cancel'))
      form = GameRoomUI::Form.new([tree, accept, cancel], program: @program, quiet: true)
      form.accept_button, form.cancel_button = accept, cancel
      chosen = nil
      accept.on(:press) do
        candidate = tree.selected.to_s
        if File.file?(candidate) && LibLouis::TABLE_EXTENSIONS.include?(File.extname(candidate).downcase)
          chosen = candidate
          form.resume
        else
          alert(label)
          form.index = 0
          tree.focus
        end
      end
      cancel.on(:press) { form.resume }
      form.wait
      chosen
    ensure
      tree&.close_preview
    end

  end
end
