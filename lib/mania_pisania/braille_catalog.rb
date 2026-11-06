# encoding: UTF-8
require_relative '../game_room_localization'
require_relative 'languages'

module GameRoomTyping
  # IDs are persistent settings/checkpoint values. Include files and display
  # mappings are not selectable translation tables.
  module BrailleCatalog
    using GameRoomLocalization::Translations
    FILES = {
      'polish_integral'=>'pl-pl-integral.utb', 'polish_g1'=>'Pl-Pl-g1.utb',
      'polish_g2'=>'Pl-Pl-g2.utb', 'polish_computer'=>'pl-pl-comp8.ctb',
      'english_g1'=>'en-ueb-g1.ctb', 'english_g2'=>'en-ueb-g2.ctb', 'english_g3'=>'en-g3.ctb',
      'english_uk_g1'=>'en-gb-g1.utb', 'english_uk_g2'=>'en-GB-g2.ctb',
      'english_uk_computer'=>'en-gb-comp8.ctb', 'english_us_g1'=>'en-us-g1.ctb',
      'english_us_g2'=>'en-us-g2.ctb', 'english_us_computer6'=>'en-us-comp6.ctb',
      'english_us_computer8'=>'en-us-comp8.ctb', 'english_us_computer8_extended'=>'en-us-comp8-ext.utb',
      'english_nabcc'=>'en-nabcc.utb', 'english_india_g1'=>'en-in-g1.ctb',
      'english_nz_g1'=>'en-nz-g1.utb', 'english_nz_g2'=>'en-nz-g2.ctb',
      'english_us_interline'=>'en-us-interline.ctb', 'english_us_mathtext'=>'en-us-mathtext.ctb',
      'czech_g1'=>'cs-g1.ctb', 'czech_computer'=>'cs-comp8.utb',
      'spanish_g1'=>'es-g1.ctb', 'spanish_g2'=>'es-g2.ctb',
      'spanish_computer'=>'Es-Es-G0.utb', 'spanish_norwegian'=>'es-no.utb',
      'russian_literary'=>'ru-litbrl.ctb', 'russian_detailed'=>'ru-litbrl-detailed.utb',
      'russian_g1'=>'ru-ru-g1.ctb', 'russian_computer6'=>'ru-comp6.utb', 'russian_computer8'=>'ru-comp8.utb'
    }.freeze
    DEFAULTS = {'en'=>'english_g1', 'pl'=>'polish_integral', 'cs'=>'czech_g1',
      'es'=>'spanish_g1', 'ru'=>'russian_literary'}.freeze

    def self.default(language)
      DEFAULTS.fetch(language.to_s.downcase.split(/[-_]/).first, 'english_g1')
    end

    def self.language(id)
      {'polish'=>'pl', 'english'=>'en', 'czech'=>'cs', 'spanish'=>'es', 'russian'=>'ru'}[id.to_s.split('_').first]
    end

    def self.visible?(id)
      Languages.visible.include?(language(id))
    end

    def self.labels
      {
        'polish_integral'=>_('Polish integral braille (uncontracted)'),
        'polish_g1'=>_('Polish literary braille, contractions grade 1'),
        'polish_g2'=>_('Polish literary braille, grade 2 (contracted)'),
        'polish_computer'=>_('Polish computer braille'),
        'english_g1'=>_('English UEB, grade 1'), 'english_g2'=>_('English UEB, grade 2'),
        'english_g3'=>_('English, grade 3'),
        'english_uk_g1'=>_('English (UK), grade 1'), 'english_uk_g2'=>_('English (UK), grade 2'),
        'english_uk_computer'=>_('English (UK), computer braille'),
        'english_us_g1'=>_('English (US), grade 1'), 'english_us_g2'=>_('English (US), grade 2'),
        'english_us_computer6'=>_('English (US), 6-dot computer braille'),
        'english_us_computer8'=>_('English (US), 8-dot computer braille'),
        'english_us_computer8_extended'=>_('English (US), extended 8-dot computer braille'),
        'english_nabcc'=>_('English, North American Braille Computer Code'),
        'english_india_g1'=>_('English (India), grade 1'),
        'english_nz_g1'=>_('English (New Zealand), grade 1'), 'english_nz_g2'=>_('English (New Zealand), grade 2'),
        'english_us_interline'=>_('English (US), interline braille'),
        'english_us_mathtext'=>_('English (US), mathematical text'),
        'czech_g1'=>_('Czech literary braille'), 'czech_computer'=>_('Czech computer braille'),
        'spanish_g1'=>_('Spanish literary braille'), 'spanish_g2'=>_('Spanish contracted braille'),
        'spanish_computer'=>_('Spanish computer braille'), 'spanish_norwegian'=>_('Spanish text in Norwegian braille'),
        'russian_literary'=>_('Russian literary braille'), 'russian_detailed'=>_('Russian braille with capital letters'),
        'russian_g1'=>_('Russian contracted braille'),
        'russian_computer6'=>_('Russian 6-dot computer braille'), 'russian_computer8'=>_('Russian 8-dot computer braille')
      }
    end
  end
end
