# encoding: UTF-8
require_relative 'text'
require_relative '../game_room_localization'

module GameRoomTyping
  class WordPrompt
    using GameRoomLocalization::Translations

    def announcement(word)
      value = KeyboardText.normalize(word)
      # Synthesizer punctuation settings must not hide characters the player
      # needs to type. Keep letter/number runs natural and name every symbol.
      text = value.scan(/[\p{L}\p{N}]+|./).map do |part|
        part.match?(/\A[\p{L}\p{N}]+\z/) ? part : character_name(part)
      end.join(' ')
      text += ' ' + _('Type the number using digits.') if value.match?(/[0-9]/)
      text
    end

    def spelling(word)
      KeyboardText.normalize(word).each_char.map { |character| character_name(character) }.join(', ')
    end

    def character_name(character)
      case character
      when ' ' then _('space')
      when '-' then _('minus')
      when '"' then _('quotation mark')
      when "'" then _('apostrophe')
      when '.' then _('full stop')
      when ',' then _('comma')
      when ':' then _('colon')
      when ';' then _('semicolon')
      when '!' then _('exclamation mark')
      when '?' then _('question mark')
      when '¿' then _('inverted question mark')
      when '¡' then _('inverted exclamation mark')
      when '(' then _('opening parenthesis')
      when ')' then _('closing parenthesis')
      when '[' then _('opening square bracket')
      when ']' then _('closing square bracket')
      when '{' then _('opening brace')
      when '}' then _('closing brace')
      when '/' then _('slash')
      when '\\' then _('backslash')
      when '%' then _('percent sign')
      when '+' then _('plus')
      when '=' then _('equals sign')
      when '*' then _('asterisk')
      when '#' then _('hash sign')
      when '@' then _('at sign')
      when '_' then _('underscore')
      when '&' then _('ampersand')
      when '<' then _('less-than sign')
      when '>' then _('greater-than sign')
      when '$' then _('dollar sign')
      when '^' then _('caret')
      when '~' then _('tilde')
      when '`' then _('backtick')
      when '|' then _('vertical bar')
      else
        if character.match?(/\p{Lu}/)
          _('capital %{letter}') % {letter: character.downcase}
        else
          character
        end
      end
    end
  end
end
