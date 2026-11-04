require_relative 'host_bridge'
require_relative "game_room_preferences"
require_relative "context_help"
require_relative "game_room_ping"
require_relative "game_room_pending_operation"
require_relative "conference_controls"

# The host handles function keys before Form events. Intercept dispatch, not
# saved QuickActions or host sources. Only a currently waiting Game Room form
# in the host's active-controls list can replace a native action. The bridge
# holds no application/runtime reference. Upgrade the legacy fixed-key bridge
# once; subsequent application reloads reuse dynamic control dispatch.
require_relative "game_room_localization"

module GameRoomUI
  using GameRoomLocalization::Translations
  HostForm = Form
  # Read-only text retains the native reading/selection/copy commands, but
  # Enter belongs to the dialog's Close button rather than a multiline editor.
  class HelpText < EditBox
    def key_processed(key)
      return false if key.to_s.sub(/\Akey_/, '') == 'enter'
      super
    end
  end
  VOLUME_LABELS = {
    "all" => "All Power Games sounds", "game" => "Game sounds",
    "room" => "Sounds when someone enters or leaves a room",
    "chat" => "Chat sounds", "notifications" => "Invitation and Power Games notification sounds"
  }.freeze
  GLOBAL_TIPS = [
    "F2: lower the selected Power Games sound volume.",
    "F3: raise the selected Power Games sound volume.",
    "Shift+F2: select the previous sound group.",
    "Shift+F3: select the next sound group.",
    "Ctrl+F4: read HTTP ping and available Communications relay or P2P ping."
  ].freeze
  HotkeyAction = Struct.new(:callback) do
    def call
      callback.call
    end
  end

  module PingControl
    attr_accessor :game_room_program

    def request_game_room_ping
      EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
      return unless game_room_program
      service = GameRoomPing.for(game_room_program)
      service.request(game_room_program)
    end

    def update_game_room_ping
      current = $activecontrols.to_a.reverse.find do |control|
        control.respond_to?(:game_room_hotkeys_active?) && control.game_room_hotkeys_active?
      end
      return unless current.equal?(self) && game_room_program
      service = game_room_program.instance_variable_get(:@game_room_ping)
      message = service&.poll(game_room_program)
      speak(message) if message
    end
  end

  module_function

  def install_hotkeys
    return unless defined?(EltenAPI::QuickActions)

    target = EltenAPI::QuickActions.singleton_class
    return if target.instance_variable_get(:@game_room_dispatch_bridge_version).to_i >= 3

    GameRoomHostBridge.prepare(target, marker: :@game_room_dispatch_bridge,
      method_name: :hotkey_actions, source: '/lib/game_room_ui.rb')
    # A lexical block retains its app namespace even without a program local.
    # Replace legacy method bodies, and compile the host bridge outside it.
    TOPLEVEL_BINDING.eval(<<~'RUBY', __FILE__, __LINE__ + 1)
      ::EltenAPI::QuickActions.singleton_class.instance_variable_get(:@game_room_dispatch_bridge).module_eval do
        def hotkey_actions(key)
          form = $activecontrols.to_a.reverse.find do |control|
            control.respond_to?(:game_room_hotkeys_active?) && control.game_room_hotkeys_active?
          end
          if form != nil && form.respond_to?(:game_room_hotkey_action)
            action = form.game_room_hotkey_action(key)
            return [action] if action != nil
          end
          super(key)
        end
      end
    RUBY
    target.instance_variable_set(:@game_room_dispatch_bridge_version, 3)
  end

  class Form < HostForm
    include PingControl
    attr_accessor :game_room_program, :game_room_volume_reader, :game_room_volume_writer
    attr_accessor :game_room_general_help_tips, :game_room_text_help_tips
    attr_accessor :game_room_background_help_enabled
    attr_accessor :game_room_entry_boundary
    attr_accessor :game_room_pending_operation
    attr_accessor :game_room_tournament_shortcut_enabled, :game_room_invitation_context_field
    attr_accessor :game_room_table_controls, :game_room_conference_refresh

    def initialize(fields, program: nil, **options)
      @game_room_program = program
      super(fields, **options)
    end

    def game_room_invitation_context?
      return false unless game_room_hotkeys_active? && @game_room_program&.respond_to?(:switch_to_invited_table, true)

      $activecontrols.to_a.reverse.find do |control|
        control.respond_to?(:game_room_hotkeys_active?) && control.game_room_hotkeys_active?
      end.equal?(self)
    end

    def hascontext
      super || game_room_invitation_context?
    end

    def context(menu, submenu = true)
      super
      return if submenu && !contextinglobal_enabled?
      if game_room_table_controls && GameRoomConferenceControls.connected? && @game_room_program&.respond_to?(:toggle_conference_microphone, true)
        menu.option(GameRoomContent.utf8(GameRoomConferenceControls.microphone_label), nil, "M") do
          @game_room_program&.__send__(:toggle_conference_microphone)
        end
      end
      return unless game_room_invitation_context?
      menu.option(GameRoomContent.utf8(_("My tournaments")),nil,"T"){open_my_tournaments} if game_room_tournament_shortcut?
      menu.option(GameRoomContent.utf8(_("Tournaments")),nil,"t"){open_tournaments} if game_room_tournament_shortcut? && @game_room_program.respond_to?(:show_tournaments,true)
      return if game_room_invitation_context_field && fields[index.to_i].equal?(game_room_invitation_context_field)

      append_game_room_invitation(menu)
    end

    def append_game_room_invitation(menu)
      return unless game_room_invitation_context?

      menu.option(GameRoomContent.utf8(_("Accept invitation")), nil, "j") do
        accept_game_room_invitation
      end
    end

    def accept_game_room_invitation
      operation = game_room_pending_operation || @game_room_help_owner&.game_room_pending_operation
      return operation.reject_action if operation
      return unless @game_room_program&.respond_to?(:switch_to_invited_table, true)

      clear_game_room_key
      begin
        @game_room_program.send(:switch_to_invited_table)
      ensure
        clear_game_room_key
      end
    end

    def game_room_tournament_shortcut?
      game_room_tournament_shortcut_enabled == true && @game_room_program&.respond_to?(:show_my_tournaments, true)
    end

    def open_my_tournaments
      return unless game_room_tournament_shortcut?
      operation=game_room_pending_operation || @game_room_help_owner&.game_room_pending_operation
      return operation.reject_action if operation
      clear_game_room_key
      @game_room_program.__send__(:show_my_tournaments)
    ensure
      clear_game_room_key
    end

    def open_tournaments
      return unless game_room_tournament_shortcut? && @game_room_program.respond_to?(:show_tournaments,true)
      operation=game_room_pending_operation || @game_room_help_owner&.game_room_pending_operation
      return operation.reject_action if operation
      clear_game_room_key
      @game_room_program.__send__(:show_tournaments)
    ensure
      clear_game_room_key
    end

    def wait
      GameRoomUI.install_hotkeys
      @game_room_waiting = true
      super
    ensure
      @game_room_waiting = false
    end

    def update
      @game_room_program.send(:announce_volume_save_error) if @game_room_program&.respond_to?(:announce_volume_save_error, true)
      game_room_conference_refresh&.call
      if game_room_table_controls && game_room_hotkeys_active? && @game_room_program&.respond_to?(:toggle_conference_microphone,true) &&
          keyboard_binding_pressed?([0x4D,:control,:shift],first:true)
        clear_game_room_key
        @game_room_program.send(:toggle_conference_microphone)
      end
      if game_room_tournament_shortcut? && game_room_hotkeys_active? && !game_room_background_help? &&
          keyboard_binding_pressed?([0x54,:control,:shift],first:true)
        open_my_tournaments
      elsif game_room_tournament_shortcut? && game_room_hotkeys_active? && !game_room_background_help? &&
          keyboard_binding_pressed?([0x54,:control],first:true)
        open_tournaments
      end
      if game_room_hotkeys_active? && @game_room_program&.respond_to?(:switch_to_invited_table, true) &&
          main_shortcut_pressed?('j', first: true)
        # Handle this before the focused field, including chat and modal forms.
        # The existing invitation path owns admission, confirmation and cleanup.
        accept_game_room_invitation
      end
      if game_room_entry_boundary && game_room_hotkeys_active? && !game_room_background_help? && !game_room_pending_operation
        @game_room_program.dispatch_game_room_entry if @game_room_program&.respond_to?(:dispatch_game_room_entry)
      end
      maintain_game_room_scene
      if game_room_background_help?
        # Keep the native game wait alive, but send keyboard input only to the
        # help form. Maintenance may resume that wait; the help/caret survives
        # the normal replay and rebind on the next pass through GameScreen.
        game_room_background_help_form.update
        @game_room_background_timers.to_a.dup.each do |timer|
          timer.update if @game_room_background_timers.include?(timer)
        end
      else
        super
      end
      update_game_room_ping
    end

    def add_timer(timer, *arguments)
      (@game_room_background_timers ||= []) << timer if timer.is_a?(FormTimer)
      super
    end

    def delete_timer(timer)
      @game_room_background_timers&.delete(timer)
      super
    end

    def focus(*arguments)
      # A replay must not refocus either the game field or the help document.
      super unless game_room_background_help?
    end

    def resume
      if @game_room_help_owner
        @game_room_help_owner.close_game_room_background_help(self)
      else
        super
      end
    end

    def game_room_background_help?
      !@game_room_help_stack.to_a.empty?
    end

    def game_room_background_help_form
      @game_room_help_stack.to_a.last&.first
    end

    def open_game_room_background_help(dialog, on_close: nil, focus: true)
      owner = @game_room_help_owner || self
      return owner.open_game_room_background_help(dialog, on_close: on_close, focus: focus) unless owner.equal?(self)

      clear_game_room_key
      (@game_room_help_stack ||= []) << [dialog, on_close]
      dialog.instance_variable_set(:@game_room_help_owner, self)
      dialog.focus if focus
      dialog
    end

    def close_game_room_background_help(dialog, restore_focus: true)
      return unless game_room_background_help_form.equal?(dialog)

      closed, cleanup = @game_room_help_stack.pop
      closed.instance_variable_set(:@game_room_help_owner, nil)
      cleanup&.call
      clear_game_room_key
      if restore_focus
        target = game_room_background_help_form || self
        target.focus
      end
    end

    def clear_game_room_background_help
      while (dialog = game_room_background_help_form)
        close_game_room_background_help(dialog, restore_focus: false)
      end
    end

    def game_room_hotkeys_active?
      @game_room_waiting == true || @game_room_help_owner != nil || game_room_pending_operation&.active? == true
    end

    def game_room_hotkey_action(key)
      return HotkeyAction.new(-> { show_game_room_help }) if key == 1
      if key == 16 && @game_room_program
        return HotkeyAction.new(-> { request_game_room_ping })
      end
      return nil unless [2, 3, -2, -3].include?(key) &&
        @game_room_program&.respond_to?(:adjust_game_room_volume, true)

      HotkeyAction.new(lambda do
        clear_game_room_key
        @game_room_program.send(
          :adjust_game_room_volume, key,
          reader: game_room_volume_reader, writer: game_room_volume_writer
        )
      end)
    end

    def show_game_room_help
      opened_here = false
      return if @game_room_help_open

      field = fields[index.to_i]
      tips = GameRoomContextHelp.field_tips(field)
      form_tips = respond_to?(:get_tips) ? get_tips.to_a : []
      history_tips = if field.is_a?(EditBox) && (field.flags.to_i & EditBox::Flags::ReadOnly) == 0
        game_room_text_help_tips.to_a
      else
        game_room_general_help_tips.to_a
      end
      global_tips = GLOBAL_TIPS.map { |tip| _(tip) }
      if @game_room_program&.respond_to?(:switch_to_invited_table, true)
        global_tips.unshift(GameRoomContextHelp.shortcut_tip('Ctrl+J', _("Accept invitation")))
      end
      global_tips.unshift(GameRoomContextHelp.shortcut_tip('Ctrl+Shift+T',_("My tournaments"))) if game_room_tournament_shortcut?
      global_tips.unshift(GameRoomContextHelp.shortcut_tip('Ctrl+T',_("Tournaments"))) if game_room_tournament_shortcut?
      global_tips.unshift(GameRoomContextHelp.shortcut_tip('Ctrl+Shift+M',_("Mute or unmute the conference microphone"))) if game_room_table_controls && @game_room_program&.respond_to?(:toggle_conference_microphone,true)
      items = GameRoomContextHelp.clean_tips(tips + form_tips + history_tips + global_tips)
      items = [_("No shortcuts are available on this screen.")] if items.empty?
      @game_room_help_open = true
      opened_here = true
      clear_game_room_key
      list = HelpText.new(GameRoomContent.utf8(_("Keyboard shortcuts")),
        type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
        text: items.map { |item| GameRoomContent.utf8(item) }.join("\n"), quiet: true)
      close = Button.new(_("Close"))
      dialog = build_game_room_help_form([list, close])
      dialog.instance_variable_set(:@game_room_help_open, true)
      dialog.game_room_volume_reader = game_room_volume_reader
      dialog.game_room_volume_writer = game_room_volume_writer
      dialog.accept_button = close
      dialog.cancel_button = close
      dialog.hide(close)
      close.on(:press) { dialog.resume }
      owner = @game_room_help_owner || (game_room_background_help_enabled ? self : nil)
      if owner
        owner.open_game_room_background_help(dialog, on_close: -> { @game_room_help_open = false })
        opened_here = false
        return
      end
      dialog.wait
      clear_game_room_key
      # A modal help view does not replace controls or modify the parent wait.
      restore_game_room_help_focus(field)
    ensure
      @game_room_help_open = false if opened_here
    end

    private

    # Lokalny ekran może przekazać lease, bez zmiany zwykłej pomocy.
    def build_game_room_help_form(fields)
      GameRoomUI::Form.new(fields, program: @game_room_program, quiet: true)
    end

    # Końcowy powrót wyłącznie z pomocy modalnej. Domyślnie zachowuje
    # dotychczasowy field.focus; lokalny guard może przejąć go w swoim ensure.
    def restore_game_room_help_focus(field)
      field.focus if field.respond_to?(:focus)
    end

    def maintain_game_room_scene
      # ELTEN 3.0.4 dispatches main and parallel scene endpoints in loop_update.
      # The form only maintains application-owned discovery/retention work.
      return unless (@game_room_waiting || game_room_pending_operation&.active?) && !@game_room_help_owner
      return unless $mainthread && $currentthread.equal?(Thread.current)
      @game_room_program.cleanup_game_room_launches if @game_room_program&.respond_to?(:cleanup_game_room_launches)
      @game_room_program.maintain_game_room_scene if @game_room_program&.respond_to?(:maintain_game_room_scene)
    end

    def clear_game_room_key
      EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
    end
  end

  # NotificationPresentation only supports a sound path, not a volume. Its
  # sound getter is read by the host at delivery, AFTER suppression/DND checks.
  # Use the app's SoundPool then and return nil to prevent a second host sound.
  module NotificationSound
    attr_accessor :game_room_notice_player

    def sound
      if !@game_room_notice_played
        @game_room_notice_played = true
        game_room_notice_player&.call
      end
      nil
    end
  end
end
