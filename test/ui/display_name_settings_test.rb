require_relative '../support/private_table_creation_encoding'

GameRoomTestLocalization.use_language('en')
GameRoomParticipants.configure_display_name(account: Session.name.to_s, name: '')
Form.option_encoding_driver = lambda do |form|
  visible = form.fields - form.hidden_controls
  field = visible.find { |control| control.is_a?(EditBox) && control.header == 'Display name' }
  raise 'Display name is absent from General' unless field && form.fields.first.index.zero?
  field.text = '  Anna   Kowalska  '
  raise 'Editing settings published an unconfirmed name' unless GameRoomParticipants.local_display_name.empty?
  form.accept_button.trigger(:press)
end
saved = GameRoomScreens::Settings.new({}, games: [], table_watch_available: false).wait
raise 'General did not normalize its saved name' unless saved['display_name'] == 'Anna Kowalska'
raise 'The form published before persistence' unless GameRoomParticipants.local_display_name.empty?

Form.option_encoding_driver = lambda do |form|
  field = (form.fields - form.hidden_controls).find { |control| control.is_a?(EditBox) && control.header == 'Display name' }
  field.text = 'Discarded Change'
  form.cancel_button.trigger(:press)
end
cancelled = GameRoomScreens::Settings.new(saved, games: [], table_watch_available: false).wait
raise 'Cancel returned a settings patch' unless cancelled.nil?
raise 'Cancel changed the input snapshot' unless saved['display_name'] == 'Anna Kowalska'
raise 'Cancel published a name' unless GameRoomParticipants.local_display_name.empty?

validation_errors = []
Form.option_encoding_driver = lambda do |form|
  field = form.fields.find { |control| control.is_a?(EditBox) && control.header == 'Display name' }
  field.text = 'x' * 65
  form.fields.first.index = 3
  form.fields.first.trigger(:move)
  form.accept_button.trigger(:press)
  raise 'Invalid name did not return to its retained General draft' unless form.fields.first.index.zero? &&
    form.fields[form.index].equal?(field) && !form.hidden_controls.include?(field) && field.text == 'x' * 65
  field.text = ''
  form.accept_button.trigger(:press)
end
cleared = GameRoomScreens::Settings.new(saved, games: [], table_watch_available: false,
  alert: ->(message) { validation_errors << message }).wait
raise 'Corrected empty name did not restore login preference' unless cleared['display_name'] == ''
raise 'Validation error was not announced once through its owner' unless validation_errors == ['Enter a single-line display name of at most 64 characters.']
puts 'PASS General display name: visible edit, normalized Save draft, Cancel and no publication before persistence'
