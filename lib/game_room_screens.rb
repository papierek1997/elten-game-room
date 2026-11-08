require_relative "context_help"
require_relative "game_room_ui"
require_relative "game_rules_view"
require_relative "readme_view"
require_relative "game_room_localization"
require_relative "axel_pong/settings"
require_relative "table_presets"

module GameRoomScreens
  using GameRoomLocalization::Translations

  MenuResult = Struct.new(:action, :index, keyword_init: true)

  class TeamList < ListBox
    def initialize(assignment, index: 0)
      @assignment = assignment
      super(rows, header: GameRoomContent.utf8(_("Players and teams")), index: index, quiet: true)
      GameRoomContextHelp.replace([self], [
        GameRoomContextHelp.shortcut_tip('Shift+Up', _("Move the selected person up")),
        GameRoomContextHelp.shortcut_tip('Shift+Down', _("Move the selected person down")),
        GameRoomContextHelp.shortcut_tip('Enter', _("Change team"))
      ])
    end

    def update
      if respond_to?(:keyboard_binding_pressed?, true)
        direction = if keyboard_binding_pressed?([:key_up, :shift])
          -1
        elsif keyboard_binding_pressed?([:key_down, :shift])
          1
        end
        if direction
          GameRoomTablePresets.consume_key(self)
          target = @assignment.move(index.to_i, direction)
          self.options = rows
          self.index = target
          focus
          return
        end
      end
      super
    end

    private

    def rows
      @assignment.players.each_with_index.map do |person, position|
        GameRoomContent.utf8(_("%{player}, team %{team}")) % {
          player: GameRoomContent.utf8(GameRoomParticipants.display_name(person)),
          team: @assignment.seats[position] + 1
        }
      end
    end
  end

  class Changelog
    def initialize(text, program: nil)
      @program = program
      @text = text
    end

    def wait
      document = EditBox.new(GameRoomContent.utf8(_("What's new")),
        type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine | EditBox::Flags::MarkDown,
        text: GameRoomContent.utf8(@text), quiet: true)
      close_button = Button.new(GameRoomContent.utf8(_("Close")))
      form = GameRoomUI::Form.new([document, close_button], program: @program, quiet: true)
      form.cancel_button = close_button
      close_button.on(:press) { form.resume }
      form.wait
    end
  end

  class Readme
    def initialize(text, program: nil)
      @program = program
      @text = text
    end

    def wait
      document = GameRoomReadmeView.new(_("README"), text: @text)
      close_button = Button.new(GameRoomContent.utf8(_("Close")))
      form = GameRoomUI::Form.new([document, close_button], program: @program, quiet: true)
      form.cancel_button = close_button
      close_button.on(:press) { form.resume }
      form.wait
    end
  end

  class MainMenu
    def initialize(options:, history_items: [], index: 0, invitations: false, refresh: nil, program: nil)
      @program = program
      @options = options
      @history_items = history_items.to_a.map(&:to_s)
      @index = index.to_i
      @invitations = invitations == true
      @refresh = refresh
    end

    def wait
      action = nil
      options = ListBox.new(
        @options,
        header: _("Power Games"),
        index: @index,
        quiet: true
      )
      require_relative 'game_history_view'
      history = GameRoomHistory::View.new(header: _("Power Games history"))
      history.replace_entries(@history_items)
      open_button = Button.new(_("Open"))
      exit_button = Button.new(_("Exit"))
      form = GameRoomUI::Form.new([options, history, open_button, exit_button], program: @program, quiet: true)
      form.game_room_tournament_shortcut_enabled = true
      form.game_room_entry_boundary = true
      form.extend(GameRoomLayout::ShortcutFormBehavior)
      navigator = GameRoomHistory::Navigator.new
      GameRoomHistory.bind(form) do |operation, value|
        entries = history.items.map { |text| GameRoomHistory::Entry.new(text: text, category: :room) }
        message = navigator.navigate(entries, operation, value, view: history,
          focused: form.fields[form.index.to_i].equal?(history))
        speak(message.to_s) unless message.to_s.empty?
      end
      form.accept_button = open_button
      form.cancel_button = exit_button
      form.hide(open_button)
      form.hide(exit_button)
      open_button.on(:press) do
        @index = options.index.to_i
        action = :open
        form.resume
      end
      exit_button.on(:press) do
        action = :exit
        form.resume
      end
      context_entries = [[:room_activity, _("Current room activity"), "w", "Ctrl+W"]]
      if @invitations
        context_entries.concat([
          [:reject_invitation, _("Reject invitation"), "J", "Ctrl+Shift+J"]
        ])
      end
      options.disable_contextinglobal
      options.bind_context do |menu|
        context_entries.each do |requested, label, key, _help_key|
          menu.option(GameRoomContent.utf8(label), nil, key) do
            next if action != nil

            @index = options.index.to_i
            action = requested
            form.resume
          end
        end
      end
      help_tips = context_entries.filter_map do |_requested, label, _key, help_key|
        GameRoomContextHelp.shortcut_tip(help_key, label) if help_key
      end
      GameRoomContextHelp.replace([options], help_tips)
      if @refresh != nil
        form.add_timer(FormTimer.new(0.5, repeat: true) do
          changed = if @refresh.arity == 0
            @refresh.call
          elsif @refresh.arity == 1
            @refresh.call(form)
          else
            @refresh.call(form, history)
          end
          next if action != nil || !changed

          @index = options.index.to_i
          action = :refresh
          form.resume
        end)
      end
      form.wait
      MenuResult.new(action: action, index: @index)
    end
  end

  class GameList < ListBox
    ACTION_ROWS = 2

    def initialize(games, header:, selected:)
      @game_count = games.size
      actions = [_("Select all games"), _("Deselect all games")].map { |label| GameRoomContent.utf8(label) }
      super(actions + games.map { |game| game.fetch(:name).to_s }, header: header,
        flags: ListBox::Flags::MultiSelection, quiet: true)
      wanted = selected.to_a.map(&:to_s)
      select_multiselection_indices(games.each_index.select { |index| wanted.include?(games[index].fetch(:id).to_s) }
        .map { |index| index + ACTION_ROWS })
      sync_action_rows
      on(:multiselection_beforechanged) { @game_changes = [] unless @applying_game_action }
      on(:multiselection_selected) { |index| record_game_change(index, true) }
      on(:multiselection_unselected) { |index| record_game_change(index, false) }
      on(:multiselection_changed) { apply_game_changes }
    end

    def game_indices
      multiselections.filter_map { |index| index - ACTION_ROWS if index >= ACTION_ROWS }
    end

    private

    def select_all_multiselection_items
      @applying_game_action = true
      super
    ensure
      @applying_game_action = false
      sync_action_rows
    end

    def deselect_all_multiselection_items
      @applying_game_action = true
      super
    ensure
      @applying_game_action = false
      sync_action_rows
    end

    def record_game_change(index, selected)
      (@game_changes ||= []) << [Array(index).first.to_i, selected] unless @applying_game_action
    end

    def apply_game_changes
      return if @applying_game_action
      changes, @game_changes = @game_changes.to_a, []
      @applying_game_action = true
      begin
        if changes.length == 1 && changes.first.first < ACTION_ROWS
          row, = changes.first
          games = (ACTION_ROWS...options.size).to_a
          row.zero? ? select_multiselection_indices(games) : deselect_multiselection_indices(games)
        end
      ensure
        @applying_game_action = false
      end
      sync_action_rows
    end

    def sync_action_rows
      count = game_indices.size
      @applying_game_action = true
      begin
        [count == @game_count && count.positive?, count.zero?].each_with_index do |checked, row|
          checked ? select_multiselection_indices([row]) : deselect_multiselection_indices([row])
        end
      ensure
        @applying_game_action = false
      end
    end
  end

  class InvitationBlacklist < ListBox
    def initialize(values)
      @names = GameRoomPreferences.invitation_blacklist(values)
      super(@names.dup, header: GameRoomContent.utf8(_("Blacklist")), quiet: true)
      disable_contextinglobal
      bind_context do |menu|
        menu.option(GameRoomContent.utf8(_("Add user")), nil, 'n') { add_user }
        menu.option(GameRoomContent.utf8(_("Remove user")), nil, :del) { remove_user } unless @names.empty?
      end
      GameRoomContextHelp.replace([self], [
        GameRoomContextHelp.shortcut_tip('Ctrl+N', _("Add user")),
        GameRoomContextHelp.shortcut_tip('Delete', _("Remove user"))
      ])
    end

    def names
      @names.dup
    end

    def add_user
      return if @editing
      begin
        @editing = true
        value = input_text(GameRoomContent.utf8(_("User name")), escapable: true)
        name = GameRoomPreferences.invitation_blacklist([value]).first
        return unless name
        @names = GameRoomPreferences.invitation_blacklist(@names + [name])
        self.options = @names.dup
        self.index = @names.index { |entry| GameRoomParticipants.same?(entry, name) }
      ensure
        @editing = false
        EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
        focus
      end
    end

    def remove_user
      return if @editing || @names.empty?
      position = index.to_i
      @names.delete_at(position)
      self.options = @names.dup
      self.index = position.clamp(0, [@names.length - 1, 0].max)
      focus
    end
  end

  class Settings
    INVITATION_POLICIES = %w[everyone contacts nobody].freeze
    attr_reader :table_watch_baseline

    def initialize(values, games:, program: nil, preset_editor: nil, preset_writer: nil,
      table_watch_available: true, table_watch_loader: nil)
      @program = program
      @values = values.to_h
      @games = games.to_a
      @hrtf_games = @games.select { |game| game[:spatial_audio] == true }
      @preset_editor = preset_editor
      @preset_writer = preset_writer
      @table_watch_available = table_watch_available
      @table_watch_loader = table_watch_loader
      @table_watch_baseline = @values["table_watch_games"].to_a.dup if table_watch_available
    end

    def wait
      action = nil
      sections = ListBox.new(
        [_("General"), _("Lobby messages"), _("Notification settings"), _("Sounds"), _("Widget")],
        header: _("Settings"), quiet: true
      )
      lobby_games = multiple_game_list(_("Games covered by lobby messages"), @values["lobby_games"])
      created = CheckBox.new(
        _("Announce when a table is created"),
        checked: setting_enabled?("announce_table_created")
      )
      joined = CheckBox.new(
        _("Announce when a player joins a table"),
        checked: setting_enabled?("announce_player_joined")
      )
      left = CheckBox.new(
        _("Announce when a player leaves a table"),
        checked: setting_enabled?("announce_player_left")
      )
      computers = CheckBox.new(
        _("Announce when a computer is added to or removed from a table"),
        checked: setting_enabled?("announce_computer_changes")
      )
      watched_header = GameRoomContent.utf8(_("Notify me about games on public tables"))
      invitation_policy, watched_games, watched_contacts, invitation_blacklist = notification_controls(watched_header)
      levels = GameRoomPreferences.sound_volumes(@values)
      volume_fields = GameRoomPreferences::SOUND_GROUPS.to_h do |group|
        [group, ListBox.new((0..100).map { |level| GameRoomContent.utf8("#{level}%") },
          header: GameRoomContent.utf8(_(GameRoomUI::VOLUME_LABELS.fetch(group))), index: levels.fetch(group), quiet: true)]
      end
      hrtf = hrtf_controls
      backgrounds, background_fields = background_music_controls
      widget_enabled = CheckBox.new(
        _("Show Power Games on the ELTEN main screen"),
        checked: setting_enabled?("widget_enabled")
      )
      widget_games = multiple_game_list(_("Games shown on the main screen"), @values["widget_games"])
      widget_unavailable = CheckBox.new(
        _("Show full or unavailable tables"),
        checked: setting_enabled?("widget_show_unavailable")
      )
      widget_contacts = CheckBox.new(
        GameRoomContent.utf8(_("Show only tables created by contacts")),
        checked: @values["widget_contacts_only"] == true
      )
      save_button = Button.new(_("Save"))
      cancel_button = Button.new(_("Cancel"))

      background_speech = CheckBox.new(GameRoomContent.utf8(_("Read table messages outside the table window")),
        checked: setting_enabled?("background_table_speech"))
      background_turn = CheckBox.new(GameRoomContent.utf8(_("Play a sound for my turn outside the table window")),
        checked: setting_enabled?("background_turn_sound"))
      background_sounds = ListBox.new([_("All games"), _("Audio games only"), _("Do not mute")].map { |text| GameRoomContent.utf8(text) },
        header: GameRoomContent.utf8(_("Mute game sounds when switching to another window")), quiet: true,
        index: %w[all audio never].index(@values["background_game_sounds"]) || 2)
      languages = GameRoomLocalization.available_languages
      language_values = GameRoomLocalization.normalize_settings(@values)
      language_labels = languages.map { |language| GameRoomContent.utf8(language.fetch(:label)) }
      primary_language = ListBox.new(language_labels,
        header: GameRoomContent.utf8(_("Primary interface language")), quiet: true,
        index: languages.index { |language| language.fetch(:id) == language_values["interface_language"] })
      known_languages = ListBox.new(language_labels,
        header: GameRoomContent.utf8(_("Known languages")), quiet: true, flags: ListBox::Flags::MultiSelection)
      known_languages.select_multiselection_indices(languages.each_index.select do |index|
        language_values["known_languages"].include?(languages[index].fetch(:id))
      end)
      [primary_language, known_languages].each do |control|
        control.add_tip(GameRoomContent.utf8(_("Missing translations use other known languages, then English. Close ELTEN completely and start it again to apply language changes; F12 is not enough.")))
      end
      presets = TablePresetList.new(@values["table_presets"], editor: @preset_editor,
        writer: @preset_writer) if @preset_editor && @preset_writer

      groups = [
        [primary_language, known_languages, background_speech, background_turn, background_sounds],
        [lobby_games, created, joined, left, computers],
        [invitation_policy, watched_games, watched_contacts, invitation_blacklist],
        hrtf + volume_fields.values + background_fields.values.flatten,
        [widget_enabled, widget_games, widget_unavailable, widget_contacts, presets].compact
      ]
      form = PresetSettingsForm.new([sections] + groups.flatten + [save_button, cancel_button], program: @program, quiet: true)
      form.preset_target = -> { sections.index.to_i == 4 ? presets : nil }
      # Function-key edits in Settings affect the same staged values as the
      # lists. Cancel discards both; Save persists them together, without I/O
      # on every arrow movement.
      form.game_room_volume_reader = -> { volume_fields.to_h { |group, field| [group, field.index.to_i] } }
      form.game_room_volume_writer = ->(group, level) { volume_fields.fetch(group).index = level }
      form.accept_button = save_button
      form.cancel_button = cancel_button
      refresh_section = lambda do
        groups.flatten.each { |control| form.hide(control) }
        groups[sections.index.to_i].to_a.each { |control| form.show(control) }
      end
      sections.on(:move) { refresh_section.call }
      refresh_section.call
      if @table_watch_loader
        loaded = false
        form.add_timer(FormTimer.new(0.1, repeat: true) do
          next if loaded
          snapshot = @table_watch_loader.call
          next if snapshot[:state] == :loading
          loaded = true
          previous = watched_games
          @table_watch_available = snapshot[:state] == :ready
          @table_watch_baseline = snapshot[:games].dup if @table_watch_available
          watched_games = if @table_watch_available
            multiple_game_list(watched_header, @table_watch_baseline)
          else
            watched_games_status(watched_header, loading: false)
          end
          # Replace one slot; all other controls, edits, category and focus
          # stay put. Hidden-state indices on the native Form are unchanged.
          position = form.fields.index(previous)
          if form.index == position
            previous.trigger(:blur)
            previous.blur if previous.respond_to?(:blur)
          end
          form.fields[position] = watched_games
          groups[2][1] = watched_games
          refresh_section.call
          watched_games.focus if form.index == position && !form.game_room_background_help?
        end)
      end
      save_button.on(:press) do
        # Native ListBox leaves Enter to the form's accept button. Handle it
        # only here, not again in :select, so one press opens one editor.
        if presets && form.fields[form.index.to_i].equal?(presets)
          presets.edit
          next
        end
        action = :save
        form.resume
      end
      cancel_button.on(:press) { form.resume }
      form.wait
      return nil if action != :save

      # Assignments are independent, immediately saved operations. Returning
      # an opening-time copy here could undo them when Settings is accepted.
      result = @values.reject { |key, _| %w[table_presets table_watch_games].include?(key) }.merge(hrtf_values(*hrtf)).merge({
        "interface_language" => languages.fetch(primary_language.index).fetch(:id),
        "background_table_speech" => background_speech.checked,
        "background_turn_sound" => background_turn.checked,
        "background_game_sounds" => %w[all audio never].fetch(background_sounds.index, "never"),
        "known_languages" => known_languages.multiselections.map { |index| languages.fetch(index).fetch(:id) },
        "lobby_games" => selected_game_ids(lobby_games),
        "lobby_known_games" => GameRoomPreferences.normalized_game_ids(
          @values["lobby_known_games"].to_a + @games.map { |game| game.fetch(:id) }
        ),
        "announce_table_created" => created.checked,
        "announce_player_joined" => joined.checked,
        "announce_player_left" => left.checked,
        "announce_computer_changes" => computers.checked,
        "announce_lobby_changes" => [created, joined, left, computers].any?(&:checked),
        "invitation_notifications" => INVITATION_POLICIES[invitation_policy.index.to_i] || "everyone",
        "invitation_blacklist" => invitation_blacklist.names,
        "table_watch_contacts_only" => watched_contacts.checked,
        "sound_volumes" => form.game_room_volume_reader.call,
        "background_music" => background_music_values(backgrounds, background_fields),
        "widget_enabled" => widget_enabled.checked,
        "widget_contacts_only" => widget_contacts.checked,
        "widget_games" => selected_game_ids(widget_games),
        "widget_known_games" => GameRoomPreferences.normalized_game_ids(
          @values["widget_known_games"].to_a + @games.map { |game| game.fetch(:id) }
        ),
        "widget_show_unavailable" => widget_unavailable.checked
      })
      result["table_watch_games"] = selected_game_ids(watched_games) if @table_watch_available
      result
    end

    private

    def background_music_controls
      backgrounds = GameRoomPreferences.background_music(@values)
      fields = %w[general game].to_h do |kind|
        track = backgrounds.fetch(kind)
        title = kind == 'general' ? _("Power Games background") : _("In-game background")
        enabled = CheckBox.new(GameRoomContent.utf8(title), checked: track['enabled'])
        choose = Button.new(background_file_label(track['file']))
        volume = ListBox.new((0..100).map { |level| GameRoomContent.utf8("#{level}%") }, quiet: true,
          header: GameRoomContent.utf8(_("Background volume")), index: track['volume'])
        choose.on(:press) do
          path = get_file(GameRoomContent.utf8(_("Select background audio or MIDI file")),
            path: Dirs.documents, save: false,
            extensions: %w[.mp3 .wav .ogg .opus .flac .m4a .aac .wma .aiff .aif .w64 .alac .webm .mod .xm .it .s3m .mid .midi .rmi])
          if path && background_file_valid?(path)
            track['file'] = path
            choose.label = background_file_label(path)
          end
        end
        [kind, [enabled, choose, volume]]
      end
      [backgrounds, fields]
    end

    def background_music_values(backgrounds, fields)
      fields.to_h do |kind, (enabled, _choose, volume)|
        [kind, backgrounds.fetch(kind).merge('enabled' => enabled.checked, 'volume' => volume.index.to_i)]
      end
    end

    def background_file_label(path)
      GameRoomContent.utf8(_("Select background file: %{file}")) % {
        file: GameRoomContent.utf8(path.to_s.empty? ? _("None") : File.basename(path.to_s)) }
    end

    def background_file_valid?(path)
      return true if background_file_openable?(path)
      alert(GameRoomContent.utf8(_("Cannot open this background file. Choose a supported audio or MIDI file.")))
      false
    end

    def background_file_openable?(path)
      return false if path.to_s.empty?
      absolute = File.expand_path(path)
      sound = ::Sound.new(absolute, sample: false) if File.file?(absolute)
      sound&.opened? == true
    rescue IOError, SystemCallError, ArgumentError
      false
    ensure
      sound&.close
    end

    def notification_controls(watched_header)
      invitation_policy = ListBox.new(
        [_("From everyone"), _("From contacts"), _("From nobody")],
        header: _("Show invitation notifications from"),
        index: [INVITATION_POLICIES.index(@values["invitation_notifications"].to_s).to_i, 0].max,
        quiet: true
      )
      invitation_blacklist = InvitationBlacklist.new(@values["invitation_blacklist"])
      watched_games = if @table_watch_available
        multiple_game_list(watched_header, @values["table_watch_games"])
      else
        watched_games_status(watched_header, loading: @table_watch_loader != nil)
      end
      watched_contacts = CheckBox.new(
        GameRoomContent.utf8(_("Notify me about new tables only from contacts")),
        checked: @values["table_watch_contacts_only"] == true
      )
      [invitation_policy, watched_games, watched_contacts, invitation_blacklist]
    end

    # The HRTF switch is followed by the games that place players' sounds.
    def hrtf_controls
      [CheckBox.new(GameRoomContent.utf8(_("Use 3D sound (HRTF) to hear other players around the table")),
        checked: @values["hrtf_enabled"] == true),
        GameList.new(@hrtf_games, header: GameRoomContent.utf8(_("Games with 3D sound")),
          selected: @values.fetch("hrtf_games", @hrtf_games.map { |game| game.fetch(:id) }))]
    end

    def hrtf_values(enabled, games)
      { "hrtf_enabled" => enabled.checked, "hrtf_games" => selected_game_ids(games, @hrtf_games),
        "hrtf_known_games" => GameRoomPreferences.normalized_game_ids(
          @values["hrtf_known_games"].to_a + @games.map { |game| game.fetch(:id) }) }
    end

    def watched_games_status(header, loading:)
      text = loading ? _("Loading notification settings") :
        _("New-table subscriptions are unavailable without access to server settings. Other settings can still be changed.")
      EditBox.new(header, type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
        text: GameRoomContent.utf8(text), quiet: true)
    end

    def multiple_game_list(header, selected)
      GameList.new(@games, header: header, selected: selected)
    end

    def selected_game_ids(control, games = @games)
      control.game_indices.filter_map { |index| games[index]&.fetch(:id)&.to_s }
    end

    def setting_enabled?(key)
      @values[key] != false
    end
  end

  class PresetSettingsForm < GameRoomUI::Form
    attr_accessor :preset_target

    def update
      target = preset_target&.call
      slot = GameRoomTablePresets.pressed_slot(self) if target
      if slot != nil
        GameRoomTablePresets.consume_key(self)
        target.index = slot
        self.index = fields.index(target)
        target.focus
      end
      super
    end
  end

  class TablePresetList < ListBox
    def initialize(values, editor:, writer:)
      @slots = GameRoomTablePresets.slots(values)
      @editor, @writer = editor, writer
      super(rows, header: GameRoomContent.utf8(_("Table shortcuts")), quiet: true)
      disable_contextinglobal
      bind_context do |menu|
        menu.option(GameRoomContent.utf8(_("Assign or edit"))) { edit }
        if @slots[index.to_i]
          menu.option(GameRoomContent.utf8(_("Clear assignment"))) { clear_assignment }
        end
      end
      tips = [GameRoomContextHelp.shortcut_tip("Enter", _("Assign or edit"))]
      tips.concat(GameRoomTablePresets::BINDINGS.each_index.map do |slot|
        GameRoomContextHelp.shortcut_tip(GameRoomTablePresets.shortcut(slot), _("Select this table shortcut for editing"))
      end)
      GameRoomContextHelp.replace([self], tips)
    end

    def edit
      return if @editing
      begin
        @editing = true
        slot = index.to_i
        entry = @editor.call(GameRoomTablePresets.slots(@slots)[slot])
        persist(slot, entry) if entry
      ensure
        @editing = false
        EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
        focus
      end
    end

    def clear_assignment
      return if @editing || !@slots[index.to_i]
      persist(index.to_i, nil)
      focus
    end

    private

    def rows
      @slots.each_with_index.map do |entry, slot|
        hint = entry ? _("Press Enter to edit.") : _("Press Enter to assign.")
        "#{GameRoomTablePresets.label(slot, entry)}. #{GameRoomContent.utf8(hint)}"
      end
    end

    def persist(slot, entry)
      begin
        @writer.call(slot, entry)
      rescue StandardError
        alert(GameRoomContent.utf8(_("The shortcut could not be saved. Please try again.")))
        return
      end
      @slots[slot] = GameRoomTablePresets.slots([entry]).first
      self.options = rows
      self.index = slot
    end
  end

  class GameRules
    def initialize(book, program: nil, game_shortcuts: nil, audio_tutorial: [])
      @program = program
      @audio_tutorial = audio_tutorial
      @book = book
      @documents = book.documents
      # Library/waiting-table help is the complete reference. During play use
      # a snapshot of the actual game fields' F1 tips, without room commands.
      if game_shortcuts != nil
        tips = GameRoomContextHelp.clean_tips(game_shortcuts)
        tips = [_("No shortcuts are available on this screen.")] if tips.empty?
        @documents = @documents.map do |document|
          document.id == :controls ? GameRoomRules::Section.new(
            id: :controls, title: document.title, paragraphs: tips) : document
        end
      end
      @section_index = 0
    end

    def wait
      loop do
        action = nil
        form = section_picker
        sections = form.fields.first
        form.accept_button.on(:press) do
          @section_index = sections.index.to_i
          action = :open
          form.resume
        end
        form.cancel_button.on(:press) do
          action = :back
          form.resume
        end
        form.wait
        return if action == :back

        if action == :open
          if @section_index == @documents.length
            GameRoomAudioTutorial.new(@audio_tutorial, program: @program).wait
          else
            section_form(@documents[@section_index]).wait
          end
        end
      end
    end

    def open_on(parent)
      form = section_picker
      form.accept_button.on(:press) do
        @section_index = form.fields.first.index.to_i
        if @section_index == @documents.length
          GameRoomAudioTutorial.new(@audio_tutorial, program: @program).open_on(parent)
        else
          parent.open_game_room_background_help(section_form(@documents[@section_index]))
        end
      end
      form.cancel_button.on(:press) { form.resume }
      parent.open_game_room_background_help(form)
    end

    private

    def section_picker
      titles = @documents.map(&:title)
      titles << GameRoomContent.utf8(_("Audio tutorial")) unless @audio_tutorial.empty?
      sections = ListBox.new(titles,
        header: _("%{game} rules") % { game: @book.title },
        index: bounded_index(@section_index, titles), quiet: true)
      open_button = Button.new(_("Open"))
      back_button = Button.new(_("Back"))
      form = GameRoomUI::Form.new([sections, open_button, back_button], program: @program, quiet: true)
      form.accept_button = open_button
      form.cancel_button = back_button
      form.hide(open_button)
      form.hide(back_button)
      form
    end

    def section_form(section)
      header = _("%{game}: %{section}") % { game: @book.title, section: section.title }
      shortcuts = section.id == :controls
      content = if shortcuts
        ListBox.new(section.paragraphs, header: header, quiet: true)
      else
        GameRoomRules::View.new(header, document: section)
      end
      back_button = Button.new(_("Back"))
      form = GameRoomUI::Form.new([content, back_button], program: @program, quiet: true)
      form.cancel_button = back_button
      form.accept_button = back_button if shortcuts
      form.instance_variable_set(:@game_room_help_open, true) if shortcuts
      form.hide(back_button)
      back_button.on(:press) { form.resume }
      form
    end

    def bounded_index(index, items)
      return 0 if items.empty?

      [[index.to_i, 0].max, items.length - 1].min
    end
  end
end
