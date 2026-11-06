# encoding: UTF-8
require_relative 'text_selection'
require_relative 'text_library_dialog'

module GameRoomTyping
  # Runs on the UI before creating/updating the ordinary PowerGames table.
  class TablePreparation
    using GameRoomLocalization::Translations

    def initialize(program, game)
      @program, @game = program, game
    end

    def alert(message); @program.send(:alert, message); end

    def prepare(options)
      return options unless options['variant'] == 'free' && options['text'] != 'own'
      unless %w[local pasted].include?(options['text'])
        # A preset may refer to an earlier edition. Publish the description of
        # the currently chosen built-in before anyone can join the new table.
        return @game.normalize_options(options.reject { |key, _| TextSelection::KEYS.include?(key) })
      end
      library = TextLibrary.new(@program)
      return options if TextSelection.resolve(options, library)
      alert(_('Choose the text in the table settings before creating or updating the table.'))
      nil
    rescue ArgumentError
      alert(_('The selected text cannot be used. Check its characters and size before choosing it again.'))
      nil
    end
  end

  # Called by the existing start boundary, without opening UI from its worker.
  class TextStartGuard
    using GameRoomLocalization::Translations

    def initialize(program); @program = program; end

    def consume(options)
      return true unless options['variant'] == 'free' && TextSelection.descriptor(options)
      return true if TextSelection.resolve(options, TextLibrary.new(@program))
      _('The selected text is no longer available on this computer. Choose it again in the table settings before starting.')
    end
  end
end
