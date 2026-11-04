# encoding: UTF-8
require_relative 'text_import_dialog'
require_relative '../game_room_ui'

module GameRoomTyping
  class TextLibraryDialog
    using GameRoomLocalization::Translations

    def initialize(program, library, on_reset: nil, alert: nil, confirm: nil)
      @program, @library, @on_reset = program, library, on_reset
      @alert = alert || ->(text) { alert(text) }
      @confirm = confirm || ->(text) { confirm(text) }
    end

    def wait(select: true)
      chosen = nil
      entries = []
      list = ListBox.new([], header: _('Texts and completion'), quiet: true)
      import = Button.new(_('Import a file or paste text'))
      reset = Button.new(_('Reset progress for the selected text'))
      close = Button.new(_('Close'))
      form = GameRoomUI::Form.new([list, import, reset, close], program: @program, quiet: true)
      form.cancel_button = close
      refresh = lambda do
        selected_id = entries[list.index.to_i]&.fetch('id')
        entries = @library.entries
        list.options = entries.map { |item| _('%{title}: %{progress}%% complete') % {title: item['title'], progress: item['progress']} }
        list.index = entries.index { |item| item['id'] == selected_id } || 0
      end
      list.on(:select) do
        if select && entries[list.index]
          chosen = entries[list.index]['id']
          form.resume
        end
      end
      import.on(:press) do
        imported = TextImportDialog.new(@program, @library).wait
        refresh.call if imported
        import.focus
      end
      reset.on(:press) do
        entry = entries[list.index.to_i]
        if entry && @confirm.call(_('Reset progress for %{title}?') % {title: entry['title']})
          begin
            @library.reset_progress(entry['id'])
            @on_reset&.call(entry['id'])
            refresh.call
            @alert.call(_('Progress reset.'))
          rescue IOError, SystemCallError => exception
            @alert.call(_('Could not save typing progress: %{reason}') % {reason: GameRoomContent.utf8(exception.message)})
          end
          form.index = 0
          list.focus
        end
      end
      close.on(:press) { form.resume }
      refresh.call
      form.wait
      chosen
    end
  end
end
