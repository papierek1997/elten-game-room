require_relative '../../support/new_games_fixture'
directory = File.expand_path('../../../locale', __dir__)
expected = {'en'=>'A raises by 100.', 'pl'=>'A podbija o 100.', 'cs'=>'A navyšuje o 100.',
  'es'=>'A sube la apuesta en 100.', 'ru'=>'A повышает ставку на 100.'}
game = GameRoomGames::Poker.new
expected.each do |language,text|
  GameRoomLocalization.boot(directory:directory, host_language:language,
    settings:{'interface_language'=>language,'known_languages'=>[]})
  state = {current_bet:50,street_bets:{'A'=>150}}
  actual = game.send(:betting_history,'A','raise',125,state,50)
  assert(actual == text, "Concise raise not translated in #{language}: #{actual}")
  book = game.send(:localized_rule_sections)
  settings = book.find { |section| section.id.to_s == 'settings' }
  assert(settings && !settings.paragraphs.empty?, "Missing blind explanation in #{language}")
end
puts 'PASS actual EN/PL/CS/ES/RU concise raises and localized blind-settings chapters'
