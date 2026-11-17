# encoding: UTF-8
require_relative 'difficulty'

module GameRoomDarts
  module Preferences
    LOCATOR_ASSETS = {
      'round' => 'darts_locator_round',
      'clear' => 'darts_locator_clear',
      'bright' => 'darts_locator_bright'
    }.freeze
    DEFAULTS = {'locator_sound'=>'round', 'public_rankings'=>false,
      'unlocked_difficulty'=>Difficulty::BASE_HIGHEST, 'unlocked_account'=>'',
      'private_records_in_history'=>false, 'mouse_input'=>true}.freeze

    module_function

    def normalize(values)
      values = values.is_a?(Hash) ? values : {}
      choice = values['locator_sound'].to_s
      account = values['unlocked_account']
      account = '' unless account.is_a?(String) && account.valid_encoding? && account.bytesize <= 64
      {'locator_sound'=>LOCATOR_ASSETS.key?(choice) ? choice : DEFAULTS['locator_sound'],
        'public_rankings'=>values['public_rankings'] == true,
        'unlocked_difficulty'=>Difficulty.normalize_highest(values['unlocked_difficulty']),
        'unlocked_account'=>account.strip.downcase,
        'private_records_in_history'=>values['private_records_in_history'] == true,
        'mouse_input'=>values.key?('mouse_input') ? values['mouse_input'] == true : DEFAULTS['mouse_input']}
    end

    def read(program)
      return DEFAULTS unless program.respond_to?(:darts_preferences, true)

      for_account(program.send(:darts_preferences), current_account)
    end

    def for_account(values, account)
      values = normalize(values)
      account = account.to_s.strip.downcase
      return values if !account.empty? && values['unlocked_account'] == account

      values.merge('unlocked_difficulty'=>Difficulty::BASE_HIGHEST, 'unlocked_account'=>account)
    end

    def current_account
      Session.name.to_s.strip.downcase if defined?(Session) && Session.respond_to?(:name)
    end

    def locator_asset(values)
      LOCATOR_ASSETS.fetch(normalize(values)['locator_sound'])
    end
  end
end
