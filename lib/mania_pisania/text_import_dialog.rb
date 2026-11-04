# encoding: UTF-8
require_relative '../game_room_ui'

module GameRoomTyping
  class TextImportDialog
    using GameRoomLocalization::Translations

    def initialize(program, library, paste_only: false)
      @program, @library = program, library
      @paste_only = paste_only
    end

    def _(text); GameRoomContent.utf8(super(text)); end

    def wait
      imported = nil
      tree = FilesTree.new(_('Choose a UTF-8 text file'), extensions: ['.txt'], quiet: true) unless @paste_only
      open, cancel = Button.new(_('Import')), Button.new(_('Cancel'))
      title = EditBox.new(_('Title of the pasted text'), text: '', quiet: true)
      pasted = EditBox.new(_('Paste text for typing practice'), type: EditBox::Flags::MultiLine, text: '', quiet: true)
      import_pasted = Button.new(_('Import pasted text'))
      fields = @paste_only ? [title, pasted, import_pasted, cancel] : [tree, open, title, pasted, import_pasted, cancel]
      form = GameRoomUI::Form.new(fields, program: @program, quiet: true, index: 0)
      form.accept_button, form.cancel_button = @paste_only ? import_pasted : open, cancel
      form.on(:move) { form.accept_button = @paste_only || form.index.to_i.between?(2, 4) ? import_pasted : open }
      open.on(:press) do
        path = tree.selected
        if File.directory?(path)
          tree.go
          form.index = 0
          tree.focus
        else
          begin
            imported = @library.import_file(path)
            form.resume
          rescue UnsupportedCharacters => exception
            unsupported(exception)
          rescue ArgumentError, IOError, SystemCallError => exception
            alert(_('Could not import the text: %{reason}') % {reason: GameRoomContent.utf8(exception.message)})
          ensure
            # A failed import keeps this very same native tree alive. Do not
            # rebuild it, reset its path or move its selected file.
            unless imported
              form.index = 0
              tree.focus
            end
          end
        end
      end
      import_pasted.on(:press) do
        begin
          imported = @library.import_text(pasted.text, title: title.text)
          form.resume
        rescue UnsupportedCharacters => exception
          unsupported(exception)
        rescue ArgumentError, IOError, SystemCallError => exception
          alert(_('Could not import the text: %{reason}') % {reason: GameRoomContent.utf8(exception.message)})
        ensure
          unless imported
            form.index = fields.index(pasted)
            form.accept_button = import_pasted
            pasted.focus
          end
        end
      end
      cancel.on(:press) { form.resume }
      form.wait
      imported
    ensure
      tree&.close_preview
    end

    private

    def unsupported(exception)
      labels = exception.characters.map { |character| "#{character} (U+#{character.ord.to_s(16).upcase})" }
      alert(_('Replace these unsupported characters in the text: %{characters}') % {characters: labels.join(', ')})
    end
  end
end
