require_relative "context_help"
require_relative "game_room_ui"
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
    def initialize(items, program: nil)
      @program = program
      @items = items.to_a.map(&:to_s)
    end

    def wait
      list = ListBox.new(@items, header: _("What's new"), index: 0, quiet: true)
      close_button = Button.new(_("Close"))
      form = GameRoomUI::Form.new([list, close_button], program: @program, quiet: true)
      form.accept_button = close_button
      form.cancel_button = close_button
      form.hide(close_button)
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
        header: _("ELTEN Game Room"),
        index: @index,
        quiet: true
      )
      require_relative 'game_history_view'
      history = GameRoomHistory::View.new(header: _("Game Room history"))
      history.replace_entries(@history_items)
      open_button = Button.new(_("Open"))
      exit_button = Button.new(_("Exit"))
      form = GameRoomUI::Form.new([options, history, open_button, exit_button], program: @program, quiet: true)
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
          [:invitations, _("Accept invitation"), "j", "Ctrl+J"],
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
      help_tips = context_entries.map do |_requested, label, _key, help_key|
        GameRoomContextHelp.shortcut_tip(help_key, label)
      end
      GameRoomContextHelp.replace([options, history], help_tips)
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

  class Settings
    INVITATION_POLICIES = %w[contacts nobody everyone].freeze

    def initialize(values, games:, program: nil, preset_editor: nil, preset_writer: nil, table_watch_available: true)
      @program = program
      @values = values.to_h
      @games = games.to_a
      @preset_editor = preset_editor
      @preset_writer = preset_writer
      @table_watch_available = table_watch_available
    end

    def wait
      action = nil
      sections = ListBox.new(
        [_("General"), _("Lobby messages"), _("Notification settings"), _("Sounds"), _("Widget"), _("Axel Pong")],
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
        _("Announce when a computer is added or removed"),
        checked: setting_enabled?("announce_computer_changes")
      )
      invitation_policy = ListBox.new(
        [_("From contacts"), _("From nobody"), _("From everyone")],
        header: _("Show invitation notifications from"),
        index: [INVITATION_POLICIES.index(@values["invitation_notifications"].to_s).to_i, 0].max,
        quiet: true
      )
      watched_header = GameRoomContent.utf8(_("Notify me about new public tables (preferences are visible to table creators)"))
      watched_games = if @table_watch_available
        multiple_game_list(watched_header, @values["table_watch_games"])
      else
        EditBox.new(watched_header, type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
          text: GameRoomContent.utf8(_("New-table subscriptions are unavailable without access to server settings. Other settings can still be changed.")), quiet: true)
      end
      watched_contacts = CheckBox.new(
        GameRoomContent.utf8(_("Notify me about new tables only from contacts")),
        checked: @values["table_watch_contacts_only"] == true
      )
      levels = GameRoomPreferences.sound_volumes(@values)
      volume_fields = GameRoomPreferences::SOUND_GROUPS.to_h do |group|
        [group, ListBox.new((0..100).map { |level| "#{level}%" },
          header: _(GameRoomUI::VOLUME_LABELS.fetch(group)), index: levels.fetch(group), quiet: true)]
      end
      widget_enabled = CheckBox.new(
        _("Show Game Room on the ELTEN main screen"),
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

      pong_fields = GameRoomPong::SettingsFields.new(@values['pong'])
      background_speech = CheckBox.new(GameRoomContent.utf8(_("Read table messages outside the table window")),
        checked: setting_enabled?("background_table_speech"))
      background_turn = CheckBox.new(GameRoomContent.utf8(_("Play a sound for my turn outside the table window")),
        checked: setting_enabled?("background_turn_sound"))
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
      known_languages.require_multiselection_indices([primary_language.index])
      primary_language.on(:move) { known_languages.require_multiselection_indices([primary_language.index]) }
      [primary_language, known_languages].each do |control|
        control.add_tip(GameRoomContent.utf8(_("Missing translations use other known languages, then English. Restart ELTEN to apply language changes.")))
      end
      presets = TablePresetList.new(@values["table_presets"], editor: @preset_editor,
        writer: @preset_writer) if @preset_editor && @preset_writer

      groups = [
        [primary_language, known_languages, background_speech, background_turn],
        [lobby_games, created, joined, left, computers],
        [invitation_policy, watched_games, watched_contacts],
        volume_fields.values,
        [widget_enabled, widget_games, widget_unavailable, widget_contacts, presets].compact,
        pong_fields.fields
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
      result = @values.reject { |key, _| %w[table_presets table_watch_games].include?(key) }.merge({
        "interface_language" => languages.fetch(primary_language.index).fetch(:id),
        "background_table_speech" => background_speech.checked,
        "background_turn_sound" => background_turn.checked,
        "known_languages" => known_languages.multiselections.map { |index| languages.fetch(index).fetch(:id) },
        "pong" => pong_fields.values,
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
        "table_watch_contacts_only" => watched_contacts.checked,
        "sound_volumes" => form.game_room_volume_reader.call,
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

    def multiple_game_list(header, selected)
      control = ListBox.new(
        @games.map { |game| game.fetch(:name).to_s },
        header: header,
        flags: ListBox::Flags::MultiSelection,
        quiet: true
      )
      wanted = selected.to_a.map(&:to_s)
      control.select_multiselection_indices(
        @games.each_index.select { |index| wanted.include?(@games[index].fetch(:id).to_s) }
      )
      control
    end

    def selected_game_ids(control)
      control.multiselections.filter_map { |index| @games[index]&.fetch(:id)&.to_s }
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
        EditBox.new(header,
          type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
          text: section.text,
          quiet: true
        )
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
