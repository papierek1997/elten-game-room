# encoding: UTF-8
require_relative '../support/settings_widget'
require_relative '../support/server_table_access'

entry = EltenGameRoom::MAIN_OPTIONS.index('Tournaments')
assert(entry, 'Brakuje wejścia do turniejów w menu Game Roomu')
assert(defined?(GameRoomTournaments::Hub), 'Aplikacja nie ładuje menu modułu turniejów')
app = EltenGameRoom.new
opened = []
labels = {
  'Create a new table' => :show_create_table, 'Join a table' => :show_join_table,
  'Game rules' => :show_rules_library, 'README' => :show_readme,
  'Create your own quiz question sets' => :show_question_creator,
  'Saved games' => :show_saved_games, 'Leaderboards' => :show_leaderboards,
  'Statistics' => :show_statistics, 'Settings' => :show_settings,
  "What's new" => :show_changelog, 'Tournaments' => :show_tournaments
}
labels.each_value { |method| app.define_singleton_method(method) { opened << method } }
EltenGameRoom::MAIN_OPTIONS.each_with_index do |label, index|
  app.send(:open_main_option, index)
  assert(opened.last == labels.fetch(label), "Menu uruchomiło złą akcję: #{label}")
end
assert(EltenGameRoom::MAIN_OPTIONS.last == "What's new", 'Zmieniono położenie ostatniej pozycji menu')

factory = GameRoomTournaments::Hub.method(:new)
received = nil
ran = false
workspace = Object.new
workspace.define_singleton_method(:run) { ran = true }
GameRoomTournaments::Hub.define_singleton_method(:new) do |**options|
  received = options
  workspace
end
begin
  instance = EltenGameRoom.new
  instance.instance_variable_set(:@server_tables, GameRoomTest::ServerTableAccess.new(:available))
  instance.send(:show_tournaments)
  assert(ran && received[:program].equal?(instance), 'Wejście menu nie uruchomiło modułu na własnym programie')
  assert(received[:registry].equal?(EltenGameRoom::GAME_REGISTRY), 'Moduł nie otrzymał rejestru wszystkich gier')
  assert(received[:user].call == Session.name, 'Moduł nie otrzymał bieżącej tożsamości użytkownika')
  expected_keys = [:program, :registry, :user, :alert, :confirm, :mine, :reference, :initial_action, :initial_phase_id]
  assert(received.keys.sort == expected_keys.sort && received[:mine] == false, 'Menu przekazało nieuzgodniony kontekst')
  assert([:reference, :initial_action, :initial_phase_id].all? { |key| received[key].nil? },
    'Zwykłe wejście z lobby wybrało niezamówiony turniej, widok lub fazę')
  calls = []
  instance.define_singleton_method(:alert) { |message| calls << [:alert, message] }
  instance.define_singleton_method(:confirm) { |message| calls << [:confirm, message]; true }
  received[:alert].call('Komunikat')
  assert(received[:confirm].call('Pytanie'), 'Utracono wynik potwierdzenia')
  assert(calls == [[:alert, 'Komunikat'], [:confirm, 'Pytanie']], 'Callbacki nie należą do bieżącego programu')
  reference = {'author' => 'alice', 'publication_key' => 'selected-tournament'}
  instance.send(:show_tournaments, mine: true, reference: reference, initial_action: :results, initial_phase_id: 'phase-2')
  assert(received.keys.sort == expected_keys.sort && received[:mine] == true, 'Szybkie wejście zmieniło kontrakt menu')
  assert(received[:reference] == reference && received[:initial_action] == :results && received[:initial_phase_id] == 'phase-2',
    'Szybkie wejście zgubiło wybrany turniej, tabelę wyników lub fazę')
ensure
  GameRoomTournaments::Hub.define_singleton_method(:new, factory)
end
puts 'PASS wejście turniejów i niezmienione akcje istniejącego menu'

# The production form and Cancel lifecycle are covered with real host controls
# by shared_hub_native_test.rb; the former own-account pilot is not shipped.
