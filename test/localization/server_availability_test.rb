require_relative '../support/quiz_creator_native'
require_relative '../../lib/game_room_availability'

tables = Struct.new(:access_state) do
  def available?; access_state == :available; end
  def stamp_required?; access_state == :stamp_required; end
end.new(:stamp_required)

terms = {'en'=>'developer mode', 'pl'=>'dewelopersk', 'cs'=>'vývojářsk',
  'es'=>'modo de desarrollo', 'ru'=>'разработчика'}
starts = {'en'=>'Rankings are unavailable', 'pl'=>'Rankingi są niedostępne',
  'cs'=>'Bez přístupu k tabulkám serveru nejsou žebříčky dostupné',
  'es'=>'Las clasificaciones no están disponibles', 'ru'=>'Рейтинги недоступны'}
english = nil
checks = 0
%w[en pl cs es ru].each do |language|
  GameRoomLocalization.boot(host_language:language, settings:{'interface_language'=>language})
  tables.access_state = :stamp_required
  messages = %i[rankings tournaments statistics invitations subscriptions room_activity].map do |feature|
    GameRoomAvailability.unavailable(feature, tables:tables, developer:false)
  end
  messages << GameRoomAvailability.startup(tables:tables, developer:false)
  messages << GameRoomAvailability.table(tables:tables, ranked:true, developer:false)
  messages << GameRoomAvailability.table(tables:tables, ranked:false, developer:false)
  tables.access_state = :unavailable
  messages << GameRoomAvailability.unavailable(:rankings, tables:tables, developer:false)
  tables.access_state = :available
  messages << GameRoomAvailability.startup(tables:tables, developer:true)
  messages << GameRoomAvailability.table(tables:tables, ranked:true, developer:true)
  english ||= messages
  assert(messages.first.start_with?(starts.fetch(language)), "#{language}: wrong ranking language")
  messages.each_with_index do |message, index|
    assert(message.encoding == Encoding::UTF_8 && message.valid_encoding?, "#{language}/#{index}: invalid Unicode")
    assert(message.include?(terms.fetch(language)), "#{language}/#{index}: missing developer-mode explanation")
    assert(message != english[index], "#{language}/#{index}: untranslated English message") unless language == 'en'
    control = EditBox.new('Availability', type:EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
      text:message, quiet:true)
    assert(control.text == message && control.text.encoding == Encoding::UTF_8, 'The native read-only control changed the message')
    checks += 1
  end
  assert(GameRoomAvailability.unavailable(:rankings, tables:tables, developer:true).nil?, 'Dev mode blocked authorized rankings')
end

GameRoomLocalization.boot(host_language:'pl', settings:{'interface_language'=>'pl'})
tables.access_state = :stamp_required
assert(GameRoomAvailability.unavailable(:tournaments, tables:tables, developer:false) ==
  'Turnieje są niedostępne bez dostępu do tabel serwera. Serwer odmówił dostępu do tabel, ponieważ ELTEN nie dostarczył potwierdzenia z oficjalnego launchera. Najprawdopodobniej używasz trybu deweloperskiego. Uruchom ELTEN przez oficjalny launcher w zwykłym trybie i ponownie otwórz Power Games.',
  'The complete Polish tournament explanation changed')
puts "PASS availability in five languages: #{checks} native text-control messages, conditional/known reasons, live language changes and authorized-dev rankings"
