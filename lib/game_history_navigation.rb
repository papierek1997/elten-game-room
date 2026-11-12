require_relative "game_room_localization"
require_relative "game_room_key_modifiers"

module GameRoomHistory
  using GameRoomLocalization::Translations
  Entry = Struct.new(:text, :category, keyword_init: true)

  def self.bind(form, &handler)
    keys = { 'comma' => -1, ',' => -1, '<' => -1, 'period' => 1, '.' => 1, '>' => 1 }
    signatures = keys.keys.flat_map { |key| [[key, [:control]], [key, [:control, :shift]]] }
    signatures.concat([['home', [:control]], ['end', [:control]]])
    form.history_navigation_signatures = signatures
    form.game_room_general_help_tips = [
      _('Ctrl+Comma: read the previous entry in the selected history category.'),
      _('Ctrl+Period: read the next entry in the selected history category.'),
      _('Ctrl+Shift+Comma: select the previous history category.'),
      _('Ctrl+Shift+Period: select the next history category.'),
      _('Ctrl+Home: read the first entry in the selected history category.'),
      _('Ctrl+End: read the last entry in the selected history category.')
    ]
    form.game_room_text_help_tips = form.game_room_general_help_tips.first(4)
    keys.merge('home' => :first, 'end' => :last).each do |key, value|
      form.on(("key_" + key).to_sym) do
        modifiers = GameRoomUI.modifiers_when_pressed(form, key.to_sym)
        next unless modifiers.include?(:control) && !modifiers.include?(:alt)
        next if [:first, :last].include?(value) && modifiers.include?(:shift)
        field = form.fields[form.index.to_i]
        next if value.is_a?(Symbol) && field.is_a?(EditBox) && (field.flags.to_i & EditBox::Flags::ReadOnly) == 0
        operation = value.is_a?(Symbol) ? :jump : (modifiers.include?(:shift) ? :category : :move)
        form.send(:getkeychar) if %w[comma period , . < >].include?(key) && form.respond_to?(:getkeychar, true)
        EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
        handler.call(operation, value)
      end
    end
  end

  class Navigator
    CATEGORIES = [:all, :game, :chat, :room].freeze

    def initialize
      @category = :all
      @position = nil
    end

    attr_reader :category

    def selected_index(entries)
      return nil if @position == nil
      indices = entries.to_a.each_index.select { |i| @category == :all || entries[i].category.to_sym == @category }
      indices[[@position, indices.length - 1].min] unless indices.empty?
    end

    def select_index(entries, index)
      indices = entries.to_a.each_index.select { |i| @category == :all || entries[i].category.to_sym == @category }
      @position = indices.index(index)
    end

    def navigate(entries, operation, value, view: nil, focused: false)
      select_index(entries, view.entry_index) if focused && operation == :move
      message = case operation
      when :category then change_category(entries, value)
      when :move then move(entries, value)
      when :jump then jump(entries, value)
      end
      selected = selected_index(entries)
      view.entry_index = selected if focused && view && selected != nil && operation != :category
      message
    end

    def change_category(entries, direction)
      index = CATEGORIES.index(@category).to_i
      @category = CATEGORIES[(index + direction.to_i) % CATEGORIES.length]
      matching = matching_entries(entries)
      @position = matching.empty? ? nil : matching.length - 1
      category_label
    end

    def move(entries, direction)
      matching = matching_entries(entries)
      return category_message(matching) if matching.empty?

      if @position == nil
        @position = matching.length - 1
      else
        @position = bounded_position(@position + direction.to_i, matching)
      end
      matching[@position].text.to_s
    end

    def jump(entries, edge)
      matching = matching_entries(entries)
      return category_message(matching) if matching.empty?

      @position = edge.to_sym == :first ? 0 : matching.length - 1
      matching[@position].text.to_s
    end

    private

    def matching_entries(entries)
      values = entries.to_a
      return values if @category == :all

      values.select { |entry| entry.category.to_sym == @category }
    end

    def bounded_position(position, entries)
      [[position.to_i, 0].max, entries.length - 1].min
    end

    def category_message(entries, include_entry: false)
      summary = _("%{category}, entries: %{count}.") % {
        category: category_label,
        count: entries.length
      }
      return summary if !include_entry || entries.empty?

      "#{summary} #{entries.last.text}"
    end

    def category_label
      case @category
      when :game
        _("Game")
      when :chat
        _("Chat")
      when :room
        _("Room events")
      else
        _("All")
      end
    end
  end
end
