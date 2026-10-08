require_relative "game_room_background"
require_relative "network_errors"
require_relative "context_help"
require_relative "table_presets"
require_relative "game_room_ui"
require_relative "table_roster_reader"

require_relative "game_room_localization"

module GameRoomWidget
  using GameRoomLocalization::Translations
  Loading = Struct.new(:label)

  class TableList < ListBox
    include GameRoomUI::PingControl
    attr_reader :snapshots

    def initialize(loader:, opener:, labeler:, id_for:, active: -> { true }, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, worker: nil, foreground: nil, manual_refresh: -> {}, creator: nil, invitations: nil, program: nil, on_visit: nil, roster: nil, table_options: nil, game_for: nil, description: nil, presets: -> { [] })
      @game_room_program = program
      @on_visit = on_visit
      @loader = loader
      @opener = opener
      @labeler = labeler
      @id_for = id_for
      @snapshots = []
      @active, @clock = active, clock
      @manual_refresh = manual_refresh
      @creator = creator
      @presets = presets
      @invitations = invitations
      @description = description
      @foreground = foreground || ->(&operation) { operation.call }
      @load_mutex = Mutex.new
      @generation = 0
      @worker_generation = nil
      @entry_refresh = false
      runtime = Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime)
      @worker = worker || GameRoomBackground::Work.new(runtime: runtime)
      @refresh_at = 0.0
      @retry_at = 0.0
      @announce_refresh = false
      @updating = false
      super(
        [],
        header: _("Power Games tables"),
        index: 0,
        quiet: true,
        empty_label: _("Loading Power Games tables")
      )
      on(:select) { open_selected }
      if roster
        @roster_reader = GameRoomTableRosterReader.new(loader: roster, selected: -> { selected_snapshot },
          id_for: @id_for, active: -> { active? && !@creating && !@entry_refresh }, speaker: ->(text) { speak(text) })
        on(:move) { @roster_reader.invalidate }
        on(:blur) { @roster_reader.invalidate }
      end
      if table_options
        @options_reader = GameRoomTableOptionsReader.new(loader: table_options, selected: -> { selected_snapshot },
          id_for: @id_for, active: -> { active? && !@creating && !@entry_refresh }, speaker: ->(text) { speak(text) }, game_for: game_for)
        on(:move) { @options_reader.invalidate }
        on(:blur) { @options_reader.invalidate }
      end
      bind_widget_actions if @creator || @invitations || @roster_reader || @options_reader || @description
    end

    def focus(*arguments)
      GameRoomUI.install_hotkeys if @game_room_program
      return if @entry_refresh || @creating
      # ListBox focuses its selected row while handling arrows. Only a host
      # entry from outside update is a real tab entry, not list navigation.
      if !@updating && active?
        @on_visit&.call
        # Preserve the original order: fetch, replace rows, then let the host
        # read the selected row. Only periodic/manual refresh runs in the
        # background; Tab must not present a previous visit's rows as current.
        refresh_on_entry
        return unless active?
      end
      super
    end

    def update
      return if @entry_refresh || @creating
      if active?
        update_game_room_ping
        @roster_reader&.update
        @options_reader&.update
        if @description && GameRoomTablePresets.pressed?(self, 'o', :control)
          GameRoomTablePresets.consume_key(self)
          read_game_description
          return
        end
        if @options_reader && GameRoomTablePresets.pressed?(self, 'r', :control)
          GameRoomTablePresets.consume_key(self)
          @options_reader.request
          return
        end
        if @roster_reader && GameRoomTablePresets.pressed?(self, 'w', :control)
          GameRoomTablePresets.consume_key(self)
          @roster_reader.request
          return
        end
        # Native first-press detection excludes repeats and checks the exact
        # modifiers. Consume here before ListBox's character search.
        if @invitations && GameRoomTablePresets.pressed?(self, 'j', :control)
          GameRoomTablePresets.consume_key(self)
          accept_invitation
          return
        end
        if @creator
          key = creation_actions.find { |item| GameRoomTablePresets.pressed?(self, item[0], item[3]) }
          if key
            GameRoomTablePresets.consume_key(self)
            create_table(key[1])
            return
          end
        end
        apply_ready_result
        if key_pressed?(0x52)
          @manual_refresh.call
          refresh(announce: true)
          return
        end
        refresh if @clock.call >= @refresh_at
      end
      @updating = true
      super
    ensure
      @updating = false
    end

    def refresh(announce: false)
      return false unless active? && !@entry_refresh && @clock.call >= @retry_at
      if @worker.busy?
        @announce_refresh ||= announce
        self.empty_label = _("Loading Power Games tables") if @snapshots.empty?
        return false
      end
      @announce_refresh ||= announce
      @refresh_at = @clock.call + 5.0
      self.empty_label = _("Loading Power Games tables") if @snapshots.empty?
      @worker_generation = @generation
      @worker.start { load_snapshots }
    end

    def close
      @roster_reader&.close
      @options_reader&.close
      @worker.close
    end

    def game_room_hotkeys_active?
      @game_room_program != nil && active?
    end

    def game_room_hotkey_action(key)
      GameRoomUI::HotkeyAction.new(-> { request_game_room_ping }) if key == 16 && game_room_hotkeys_active?
    end

    private

    def creation_actions
      @creation_actions ||= [["n", nil, _("Create a new table"), :control]] + GameRoomTablePresets::BINDINGS.each_with_index.map do |(key, modifier), index|
        [key, index, GameRoomContent.utf8(_("Create a table from preset %{number}")) % {number: GameRoomTablePresets.shortcut(index)}, modifier]
      end
    end

    def bind_widget_actions
      # The widget lives inside ELTEN's main screen, not a Game Room Form.
      # Do not register these shortcuts globally or on other main-screen tabs.
      disable_contextinglobal
      bind_context do |menu|
        menu.option(GameRoomContent.utf8(_("Game description")), nil, "o") { read_game_description } if @description
        menu.option(GameRoomContent.utf8(_("Read the table variant and settings")), nil, "r") { @options_reader.request } if @options_reader
        menu.option(GameRoomContent.utf8(_("Read the table participants")), nil, "w") { @roster_reader.request } if @roster_reader
        menu.option(GameRoomContent.utf8(_("Accept invitation")), nil, "j") { accept_invitation } if @invitations
        saved = GameRoomTablePresets.slots(@presets.call) if @creator
        (@creator ? creation_actions : []).each do |key, slot, label, modifier|
          next if slot != nil && saved[slot] == nil
          label = GameRoomTablePresets.title(saved[slot]) if slot != nil
          shortcut = modifier == :control ? key : GameRoomTablePresets.shortcut(slot).downcase.tr("+", "_").to_sym
          menu.option(GameRoomContent.utf8(label), nil, shortcut) { create_table(slot) }
        end
      end
      tips = (@creator ? creation_actions : []).map { |_key, slot, label| GameRoomContextHelp.shortcut_tip(slot == nil ? 'Ctrl+N' : GameRoomTablePresets.shortcut(slot), label) }
      tips.unshift(GameRoomContextHelp.shortcut_tip('Ctrl+O', _("Game description"))) if @description
      tips.unshift(GameRoomContextHelp.shortcut_tip('Ctrl+J', _("Accept invitation"))) if @invitations
      tips.unshift(GameRoomContextHelp.shortcut_tip('Ctrl+W', _("Read the table participants"))) if @roster_reader
      tips.unshift(GameRoomContextHelp.shortcut_tip('Ctrl+R', _("Read the table variant and settings"))) if @options_reader
      tips << GameRoomContent.utf8(_("Ctrl+F4: read HTTP ping and available Communications relay or P2P ping.")) if @game_room_program
      GameRoomContextHelp.replace([self], tips)
    end

    def read_game_description
      return unless active? && !@creating && !@entry_refresh
      snapshot = selected_snapshot
      return unless snapshot && @description

      text = GameRoomContent.utf8(@description.call(snapshot).to_s)
      speak(text) unless text.empty?
    end

    def accept_invitation
      return if !@invitations || @creating || @entry_refresh || !active?
      begin
        # The host can pump this control while the normal invitation picker
        # or table is open. Share the guard with table creation.
        @creating = true
        @invitations.call
      rescue StandardError => error
        Log.warning("ELTEN Game Room widget invitation failed: #{error.class}: #{error.message}") if defined?(Log)
        alert(_("The operation could not be completed. Please try again."))
      ensure
        @creating = false
      end
    end

    def create_table(slot)
      return if @creating || @entry_refresh || !active?
      begin
        @creating = true
        @creator.call(slot)
      rescue StandardError => error
        Log.warning("ELTEN Game Room widget creation failed: #{error.class}: #{error.message}") if defined?(Log)
        alert(_("The table could not be created. Please try again."))
      ensure
        @creating = false
      end
    end

    def active?
      !@worker.closed? && @active.call
    end

    def load_snapshots
      # A previous timer fetch may still be finishing when Tab returns. Never
      # issue overlapping discovery requests; its result is generation-tagged.
      @load_mutex.synchronize { @loader.call }
    end

    def refresh_on_entry
      @roster_reader&.invalidate
      @options_reader&.invalidate
      @entry_refresh = true
      @generation += 1
      @announce_refresh = false
      @worker.take # discard a response prepared before this entry
      if @clock.call < @retry_at
        clear_failed_entry
        return false
      end
      result = @foreground.call do
        begin
          [load_snapshots, nil]
        rescue StandardError => error
          [nil, error]
        end
      end
      apply_result(*(result || [nil, nil]), announce: false, clear_on_error: true)
    rescue StandardError => error
      apply_result(nil, error, announce: false, clear_on_error: true)
    ensure
      @entry_refresh = false
    end

    def clear_failed_entry
      @snapshots = []
      self.options = []
      self.index = 0
      self.empty_label = _("Power Games tables could not be loaded. Press R to retry.")
    end

    def apply_ready_result
      result = @worker.take
      return unless result
      if @worker_generation != @generation
        @refresh_at = 0.0 if @announce_refresh
        return
      end

      apply_result(*result, announce: true)
    end

    def apply_result(loaded, error, announce:, clear_on_error: false)
      if loaded.is_a?(Loading) && !error
        @snapshots = []
        self.options = []
        self.index = 0
        self.empty_label = loaded.label
        @retry_at = 0.0
        @refresh_at = @clock.call + 5.0
        # Say the first actual result once if the user is still here; do not
        # mistake a pending contact read for an empty or failed table list.
        @announce_refresh = true
        return false
      end
      if error || loaded == nil
        delay = error ? GameRoomNetworkErrors.retry_delay(error, normal: 15.0, rate_limit: 60.0) : 15.0
        @retry_at = @clock.call + delay
        @refresh_at = @retry_at
        message = _("Power Games tables could not be loaded. Press R to retry.")
        clear_failed_entry if clear_on_error
        self.empty_label = message if @snapshots.empty?
        speak(message) if announce && @announce_refresh
        @announce_refresh = false
        Log.warning("ELTEN Game Room main tab refresh failed: #{error.class}: #{error.message}") if error && defined?(Log)
        return
      end
      @retry_at = 0.0
      @refresh_at = @clock.call + 5.0
      @snapshots = loaded.to_a
      # Native keys preserve the selection at delivery time, including moves
      # made while the request was pending.
      update_options(@snapshots.map { |snapshot| @labeler.call(snapshot) },
        keys: @snapshots.map { |snapshot| @id_for.call(snapshot).to_s })
      self.empty_label = _("No matching Power Games tables")
      # Native sayoption only reads actual rows and is silent for empty lists.
      if announce && @announce_refresh
        @snapshots.empty? ? speak(empty_label) : sayoption
      end
      @announce_refresh = false
      true
    end

    def open_selected
      snapshot = selected_snapshot
      return if snapshot == nil

      @opener.call(snapshot)
      refresh
    rescue StandardError => error
      Log.warning("ELTEN Game Room main tab open failed: #{error.class}: #{error.message}") if defined?(Log)
      alert(_("The table could not be opened. Please try again."))
    end

    def selected_snapshot
      @snapshots[index.to_i]
    end

  end
end
