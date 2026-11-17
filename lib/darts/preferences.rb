# encoding: UTF-8
module GameRoomDarts
  module Preferences
    LOCATOR_ASSETS = {
      'round' => 'darts_locator_round',
      'clear' => 'darts_locator_clear',
      'bright' => 'darts_locator_bright'
    }.freeze
    DEFAULTS = {'locator_sound'=>'round', 'public_rankings'=>false,
      'private_records_in_history'=>false, 'mouse_input'=>true}.freeze

    module_function

    def normalize(values)
      values = values.is_a?(Hash) ? values : {}
      choice = values['locator_sound'].to_s
      {'locator_sound'=>LOCATOR_ASSETS.key?(choice) ? choice : DEFAULTS['locator_sound'],
        'public_rankings'=>values['public_rankings'] == true,
        'private_records_in_history'=>values['private_records_in_history'] == true,
        'mouse_input'=>values.key?('mouse_input') ? values['mouse_input'] == true : DEFAULTS['mouse_input']}
    end

    def read(program)
      return DEFAULTS unless program.respond_to?(:darts_preferences, true)

      normalize(program.send(:darts_preferences))
    end

    def locator_asset(values)
      LOCATOR_ASSETS.fetch(normalize(values)['locator_sound'])
    end
  end
end
