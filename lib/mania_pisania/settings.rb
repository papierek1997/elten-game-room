# encoding: UTF-8
require_relative '../game_room_localization'
require_relative 'braille_catalog'

module GameRoomTyping
  # Local preferences only. Failed writes leave the working configuration
  # intact, including when a table is changed from an open practice screen.
  class Settings
    using GameRoomLocalization::Translations
    STORE = 'mania_pisania/settings.json'.freeze
    ECHO_MODES = %w[system none characters words characters_and_words].freeze
    DEFAULTS = {'braille_table' => 'polish_integral', 'error_speech' => true, 'error_sounds' => true,
      'music_volume' => 100, 'typing_echo' => 'system'}.freeze
    attr_reader :values

    def initialize(program)
      @program = program
      @values = normalize(program.read_json(STORE, default: {})).freeze
    end

    def [](key); @values.fetch(key); end

    def typing_echo
      mode = self['typing_echo']
      return mode unless mode == 'system'
      configured = defined?(::Configuration) ? ::Configuration.typingecho.to_s : 'none'
      ECHO_MODES.drop(1).include?(configured) ? configured : 'none'
    end

    def save(changes)
      values = normalize(@values.merge(changes))
      raise IOError, _('Could not save typing settings.') if @program.write_json(STORE, values) == false
      @values = values.freeze
    end

    private

    def normalize(raw)
      source = raw.is_a?(Hash) ? raw : {}
      language = GameRoomLocalization.primary_language
      language = Languages.visible.first unless Languages.visible.include?(language)
      defaults = DEFAULTS.merge('braille_table' => BrailleCatalog.default(language))
      defaults.to_h do |key, default|
        value = source.fetch(key, default)
        normalized = case key
        when 'braille_table'
          if !value.is_a?(String) || value.empty? || (BrailleCatalog::FILES.key?(value) && !BrailleCatalog.visible?(value))
            default
          else
            value
          end
        when 'music_volume' then value.is_a?(Integer) ? [[value, 0].max, 100].min : default
        when 'typing_echo' then ECHO_MODES.include?(value) ? value : default
        else value == true
        end
        [key, normalized]
      end
    end
  end
end
