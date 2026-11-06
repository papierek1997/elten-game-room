# encoding: UTF-8
require_relative 'text_selection'
require_relative 'text_library_dialog'

module GameRoomTyping
  # Local controls on the ordinary table-options form. Only the bounded
  # descriptor leaves this object; source prose never becomes table metadata.
  class OptionFields
    using GameRoomLocalization::Translations
    attr_reader :fields

    def initialize(program, options)
      @library = TextLibrary.new(program)
      item = TextSelection.resolve(options, @library) if %w[local pasted].include?(options['text'])
      @title = EditBox.new(_('Title of the pasted text'), text: item ? item['title'] : '', quiet: true)
      @text = EditBox.new(_('Paste text for typing practice'), type: EditBox::Flags::MultiLine,
        text: item ? item['text'] : '', quiet: true)
      @entries = @library.entries
      @local = ListBox.new(@entries.map { |entry| GameRoomContent.utf8(entry['title']) },
        header: _('Local text'), index: @entries.index { |entry| entry['id'] == item&.[]('id') }.to_i, quiet: true)
      @manage = Button.new(_('Local texts and progress'))
      @manage.on(:press) do
        previous = @entries[@local.index.to_i]&.[]('id')
        chosen = TextLibraryDialog.new(program, @library).wait
        @entries = @library.entries
        @local.options = @entries.map { |entry| GameRoomContent.utf8(entry['title']) }
        @local.index = @entries.index { |entry| entry['id'] == (chosen || previous) }.to_i
      end
      @fields = [@title, @text, @local, @manage]
    end

    def refresh(options, form)
      pasted = options['variant'] == 'free' && options['text'] == 'pasted'
      local = options['variant'] == 'free' && options['text'] == 'local'
      [[@title, pasted], [@text, pasted], [@local, local], [@manage, local]].each do |field, visible|
        visible ? form.show(field) : form.hide(field)
      end
    end

    def prepare(options)
      return options unless options['variant'] == 'free' && %w[local pasted].include?(options['text'])
      id = if options['text'] == 'pasted'
        @library.import_text(@text.text, title: @title.text, update_title: true)
      else
        @entries.fetch(@local.index.to_i).fetch('id')
      end
      options.merge(TextSelection.describe(id, @library.fetch(id)))
    rescue UnsupportedCharacters => error
      characters = error.characters.map { |character| "#{character} (U+#{character.ord.to_s(16).upcase})" }
      raise ArgumentError, _('Replace these unsupported characters in the text: %{characters}') % {characters: characters.join(', ')}
    end
  end
end
