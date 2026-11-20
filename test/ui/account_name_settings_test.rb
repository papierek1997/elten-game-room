require_relative '../support/private_table_creation_encoding'

GameRoomTestLocalization.use_language('en')
original = {'display_name'=>"Old\nName", 'game_sounds'=>false}
Form.option_encoding_driver = lambda do |form|
  raise 'The retired name field remains in Settings' if form.fields.any? { |control| control.respond_to?(:header) && control.header == 'Display name' }
  form.accept_button.trigger(:press)
end
saved = GameRoomScreens::Settings.new(original, games: [], table_watch_available: false).wait
raise 'An old name was saved by the settings form' if saved.key?('display_name')
raise 'Removing the name changed another setting' unless saved['game_sounds'] == false
Form.option_encoding_driver = ->(form) { form.cancel_button.trigger(:press) }
cancelled = GameRoomScreens::Settings.new(original, games: [], table_watch_available: false).wait
raise 'Cancel returned a settings patch' unless cancelled.nil?
raise 'The form changed the caller snapshot' unless original['display_name'] == "Old\nName"
puts 'PASS native General settings: no alias control or validation, old name omitted on Save, Cancel and other preferences unchanged'
