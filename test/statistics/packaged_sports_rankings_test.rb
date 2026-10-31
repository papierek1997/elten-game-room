require_relative '../support/binary_rules_load'
require_relative '../../lib/sports_rankings/screen'

schema=GameRoomSportsRankings::Schema::TABLES
schema.each { |name,definition| raise 'Packaged sports schema differs' unless EltenGameRoom::SERVER_TABLES.fetch(name)==definition }
games=%w[axel_pong audio_ball].map { |id| EltenGameRoom::GAME_REGISTRY.build(id) }
raise 'Sports games still expose leaderboards' if games.any?(&:supports_leaderboards?)
raise 'Sports games missing statistics capability' unless games.all?(&:supports_player_statistics?)
raise 'Retired sports ranking formula remains' if GameRoomSportsRankings::Result.respond_to?(:points)
expected={'pl'=>'Wygrane mecze: 2','en'=>'Matches won: 2','cs'=>'Vyhrané zápasy: 2','es'=>'Victorias: 2','ru'=>'Победы: 2'}
played={'pl'=>'Rozegrane mecze: 3','en'=>'Matches played: 3','cs'=>'Odehrané zápasy: 3','es'=>'Partidos jugados: 3','ru'=>'Сыграно матчей: 3'}
opponents={'pl'=>'Przeciwnicy','en'=>'Opponents','cs'=>'Soupeři','es'=>'Rivales','ru'=>'Соперники'}
all_time={'pl'=>'Cały okres','en'=>'All time','cs'=>'Celé období','es'=>'Todo el período','ru'=>'Всё время'}
row={'user'=>'Alice','won'=>2,'lost'=>1,'scored'=>24,'conceded'=>18}
expected.each do |language,label|
  GameRoomTestLocalization.use_language(language)
  screen=GameRoomSportsRankings::Screen.new(program:Object.new,game:games.first,service:nil)
  text=screen.send(:statistics_text,row)
  raise "Missing sports translation: #{language}" unless text.include?(label) && text.lines.first.chomp==played.fetch(language)
  raise "Missing opponents translation: #{language}" unless GameRoomContent.utf8(GameRoomLocalization.translate('Opponents'))==opponents.fetch(language)
  raise 'Internal ranking points leaked into details' if text.include?('1.234567') || text.lines.size!=7
  raise 'Binary sports text has wrong encoding' unless text.encoding==Encoding::UTF_8 && text.valid_encoding?
  labels=screen.send(:period_labels).map { |value| GameRoomContent.utf8(value) }
  raise "Statistics periods are not translated: #{language}" unless labels.first==all_time.fetch(language)
  if language!='en'
    raise "Statistics period labels fell back to English: #{language}" unless labels.none? { |value| value.start_with?('Last ') }
  end
end
%w[result game store service runtime screen personal].each do |name|
  path=File.join(BinaryRulesLoad::ROOT,"lib/sports_rankings/#{name}.rb")
  raise "Sports source did not load from binary: #{name}" unless BinaryRulesLoad.instance_variable_get(:@loaded)[path]
end
puts 'PASS binary sports statistics: unranked game capabilities, preserved schema, all five UI languages, seven counters and the opponents list'
