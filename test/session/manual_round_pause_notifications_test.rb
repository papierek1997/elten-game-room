require_relative '../support/session_runner'
require_relative '../../games/poker'
require_relative '../../lib/game_event_presenter'

game = GameRoomGames::Poker.new
h = NativeRoomHarness.new(game: game, users: %w[Alice Bob])
h.add_client('Watcher')
assert(h.join('Watcher'), 'Observer could not join the notification fixture')
h.as('Watcher') { h.transports['Watcher'].set_observer(h.table, true, actor: 'Watcher') }
h.start
viewers = %w[Alice Bob Watcher]
spoken, presenters, activities = {}, {}, {}
viewers.each do |user|
  spoken[user] = []
  activities[user] = TableActivityRepository.new(server_tables: Object.new, transport: h.transports[user])
  presenters[user] = GameRoomEventPresenter.new(game: game, repository: h.repositories[user], program: -> { Object.new },
    viewer: -> { user }, client: -> {}, surface_state: -> {}, clock: -> { 0 }, covered: -> { false },
    speech: ->(text) { spoken[user] << text }, trace: ->(*) {}, history_changed: -> {}, session_changed: -> {})
end
present = lambda do |user|
  entries = activities[user].entries_for(h.table, viewer: user)
  presenters[user].process_table_activity(entries, viewer: user,
    text: ->(entry) { activities[user].text_for(entry, game_name: ->(_) { 'Poker' }) })
end
viewers.each { |user| present.call(user) }
snapshot = h.repositories['Alice'].snapshot_for(h.session)
h.as('Alice') { h.transports['Alice'].freeze_game(snapshot.session, round_pause: true) }
viewers.each { |user| 3.times { present.call(user) } }
snapshot = h.repositories['Alice'].snapshot_for(h.session)
h.as('Alice') do
  h.transports['Alice'].freeze_game(snapshot.session, frozen: false, round_pause: true,
    expected_boundary: snapshot.session['__game_boundary'])
end
viewers.each do |user|
  3.times { present.call(user) }
  assert(spoken[user] == ['Game paused.', 'Game resumed.'], "#{user}: missing/repeated pause feedback: #{spoken[user].inspect}")
end

entries = activities['Alice'].entries_for(h.table, viewer: 'Alice').select { |entry| %w[game_paused game_resumed].include?(entry.kind) }
expected = {'en' => ['Game paused.', 'Game resumed.'], 'pl' => ['Gra zatrzymana.', 'Wznowiono grę.'],
  'cs' => ['Hra je pozastavena.', 'Hra byla obnovena.'], 'es' => ['Partida en pausa.', 'Partida reanudada.'],
  'ru' => ['Игра приостановлена.', 'Игра возобновлена.']}
expected.each do |language, texts|
  GameRoomLocalization.boot(directory: File.expand_path('../../locale', __dir__), host_language: language,
    settings: {'interface_language' => language, 'known_languages' => []})
  actual = entries.map { |entry| activities['Alice'].text_for(entry, game_name: ->(_) { 'Poker' }) }
  assert(actual == texts, "#{language}: untranslated pause feedback: #{actual.inspect}")
end
puts 'PASS native pause feedback: host, guest and observer, once per boundary despite refresh, binary EN/PL/CS/ES/RU'
