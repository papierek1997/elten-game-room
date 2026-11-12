# encoding: UTF-8
require_relative '../mania_pisania/braille'
require_relative '../game_room_localization'

module GameSurfaces
  # Native EditBox supplies Unicode keyboard input, including Polish AltGr
  # combinations. Input is consumed locally; typing never submits a game move.
  class TypingField < RefreshAwareEditBox
    attr_accessor :on_character, :braille_input
    DOT_KEYS = {'f' => 0x46, 'd' => 0x44, 's' => 0x53, 'j' => 0x4a, 'k' => 0x4b, 'l' => 0x4c,
      'a' => 0x41, ';' => 0xba}.freeze
    MODIFIER_KEYS = [0x10, 0x11, 0x12, 0x5b, 0x5c].freeze

    def initialize(header)
      super(header, type: 0, text: '', quiet: true, max_length: 512)
      @pending, @chord, @shown = [], [], ''
      @blocked_dots = []
    end

    def update
      super
      # Editing shortcuts/paste are not key-by-key typing. Restore the buffer
      # supplied by the engine, including after a native Backspace operation.
      set_text(@shown) unless text.to_s == @shown
      @pending << "\b" if key_pressed?(0x08, repeat: true)
      pending, @pending = @pending, []
      return update_braille(pending) if @braille_input

      pending.each { |character| @on_character&.call(character) }
    end

    def display(buffer)
      @shown = buffer.dup
      set_text(@shown) unless text.to_s == @shown
      restore_selection(index: @shown.length, check: @shown.length)
    end

    def blur
      @pending, @chord, @blocked_dots = [], [], []
      super if defined?(super)
    end

    private

    def editupdate
      @typing_edit_update = true
      super
    ensure
      @typing_edit_update = false
    end

    def espeech(text)
      # Local practice owns typing echo, including Backspace. Native espeech
      # defers output until another update, which can cancel the next prompt.
      # Navigation outside editupdate retains its ordinary native readout.
      super unless @typing_edit_update
    end

    def update_braille(pending)
      # getkeychar defaults to a single translated key. A braille chord must
      # instead read all physical presses, including taps released this frame.
      pressed = DOT_KEYS.keys.select { |key| key_pressed?(DOT_KEYS.fetch(key)) }
      down = DOT_KEYS.keys.select { |key| held_in_frame?(DOT_KEYS.fetch(key)) }
      modified = MODIFIER_KEYS.any? { |code| held_in_frame?(code) }
      modified_presses = pressed.select do |key|
        respond_to?(:keyboard_modifier_held_when_pressed?, true) &&
          [:shift, :control, :option, :command].any? { |modifier| keyboard_modifier_held_when_pressed?(DOT_KEYS.fetch(key), modifier) }
      end
      @blocked_dots |= modified_presses
      if modified
        @chord = []
        @blocked_dots |= down | pressed
      else
        @chord |= (down | pressed) - @blocked_dots
      end
      @blocked_dots &= down

      # Send the last cell before its word separator, not after it. Space can
      # also finish a chord still held; suppress those keys until released.
      if !@chord.empty? && (down.empty? || pending.include?(' '))
        cell = GameRoomTyping::SixKeyChord.cell(@chord)
        @chord = []
        @blocked_dots |= down
        @on_character&.call(cell) if cell
      end
      return if modified
      pending.each do |character|
        next if DOT_KEYS.key?(character.downcase)
        @on_character&.call(character)
      end
    end

    def held_in_frame?(code)
      # Native key_held? may already see a later Windows key state. Use the
      # same snapshot as pressed? so a partial release cannot split a chord.
      if defined?(EltenAPI::KeyboardState)
        EltenAPI::KeyboardState.held?(code)
      else
        key_held?(code)
      end
    end

    def getkeychar(*arguments)
      super.to_s.each_char { |character| @pending << character if @pending.length < 128 }
      ''
    end
  end

  class TypingSurface
    using GameRoomLocalization::Translations
    include ActionEmitter
    attr_accessor :on_character, :on_command
    attr_reader :spec

    def initialize(spec, state: {})
      @spec = spec
      @input = TypingField.new(spec.auto_commit ? _('Type here; words finish automatically') : _('Type here; Space ends the word'))
      @input.on_character = ->(character) { @on_character&.call(character) if @spec.enabled }
      @spell = Button.new(_('Spell the current word (Ctrl+L)'))
      @repeat = Button.new(_('Read the current word (Ctrl+O)'))
      @word_rest = Button.new(_('Read the rest of the word (Ctrl+;)'))
      @word_rest.on(:press) { handle_command('typing_word_rest') }
      @sentence = Button.new(_('Read the rest of the sentence (Ctrl+Shift+;)'))
      @finish = Button.new(_('Finish typing'))
      @spell.on(:press) { handle_command('typing_spell') }
      @repeat.on(:press) { handle_command('typing_repeat') }
      @sentence.on(:press) { handle_command('typing_sentence') }
      @finish.on(:press) { handle_command('typing_finish') }
      @choose_text = Button.new(_('Share the table text'))
      @choose_text.on(:press) { handle_command('typing_choose_text') }
      @commands = spec.commands.to_a.map do |command|
        button = Button.new(command.label)
        button.on(:press) { emit_action('command', command.id, command.payload || {}) }
        button
      end
      @information = RefreshAwareEditBox.new(_('Typing status'), type: EditBox::Flags::ReadOnly,
        text: spec.status.to_s, quiet: true)
    end

    def fields
      @spec.enabled ? [@input, @spell, @repeat, (@word_rest if @spec.remaining_word), (@sentence if @spec.remaining_sentence), @finish].compact :
        [@information, (@choose_text if @spec.choose_text), *@commands].compact
    end

    def state; {}; end
    def reusable_for?(spec)
      spec.is_a?(TypingSpec) && spec.round == @spec.round && spec.enabled == @spec.enabled &&
        spec.remaining_sentence == @spec.remaining_sentence &&
        spec.remaining_word == @spec.remaining_word && spec.auto_commit == @spec.auto_commit && spec.choose_text == @spec.choose_text &&
        spec.commands.to_a == @spec.commands.to_a
    end
    def update_spec(spec)
      @spec = spec
      @information.set_text(spec.status.to_s)
      self
    end

    def present(buffer:, braille:)
      @input.braille_input = braille
      @input.display(buffer)
    end

    def handle_command(command, _payload = {})
      return false unless %w[typing_spell typing_repeat typing_finish typing_status typing_sentence typing_word_rest typing_choose_text].include?(command)
      return false if command == 'typing_sentence' && !@spec.remaining_sentence
      return false if command == 'typing_word_rest' && !@spec.remaining_word
      return false if command == 'typing_choose_text' && !@spec.choose_text
      @on_command&.call(command)
      true
    end

    def submit_result(result)
      emit_action('typing', 'result', {'round' => @spec.round, 'result' => result})
    end
  end
end
