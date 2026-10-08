require_relative '../support/game_option_form'
require_relative '../support/localization'

root = File.expand_path('../..', __dir__)
expected = JSON.parse(File.read(File.join(root, 'test/fixtures/game_descriptions_pl.json'), encoding: 'UTF-8'))
registry = EltenGameRoom::GAME_REGISTRY
assert(registry.ids.sort == expected.keys.sort, 'Every game needs an approved short description')
GameRoomTestLocalization.use_language('en')
english = registry.ids.to_h { |id| [id, registry.build(id).short_description] }
languages = JSON.parse(File.read(File.join(root, 'manifest.json'))).fetch('supported_languages')
app = EltenGameRoom.allocate

languages.each do |language|
  GameRoomTestLocalization.use_language(language)
  catalog = GameRoomLocalization::Catalog.new(File.binread(File.join(root, "locale/#{language.upcase}.mo"))) unless language == 'en'
  registry.ids.each do |id|
    game = registry.build(id)
    description = game.short_description
    assert(description.encoding == Encoding::UTF_8 && description.valid_encoding?, "#{language}/#{id}: wrong encoding")
    assert(!description.empty? && !description.include?("\n"), "#{language}/#{id}: missing or multiline description")
    assert(description == expected.fetch(id), "#{id}: changed the approved Polish wording") if language == 'pl'
    assert(catalog.translate(english.fetch(id)) == description, "#{language}/#{id}: untranslated description") unless language == 'en'
    assert(app.send(:game_lobby_label, id) == "#{game.name}. #{description}", "#{language}/#{id}: name or description missing")
  end
end
assert(app.send(:game_lobby_label, 'future_game') == 'future_game', 'Unknown game broke the list')
assert(GameRoomGames::Base.new.short_description == '', 'New game without a description cannot be listed')

GameRoomTestLocalization.use_language('pl')
selected = nil
app.define_singleton_method(:configure_game_options) { |game, **| selected = game.id; nil }
app.define_singleton_method(:run_network_task) { |*| raise 'Choosing a game made a network request' }
Form.driver = lambda do |form|
  list = form.fields.first
  ids = registry.ids
  assert(list.options == ids.map { |id| app.send(:game_lobby_label, id) }, 'Creation list does not announce descriptions')
  list.index = ids.index('uno')
  form.accept_button.trigger(:press)
end
app.send(:show_create_table)
assert(selected == 'uno', 'Adding descriptions changed the selected game')
Form.driver = ->(form) { form.cancel_button.trigger(:press) }
selected = nil
app.send(:show_create_table)
assert(selected.nil?, 'Cancelled creation opened game settings')

# Other callers keep their simple names; choosing rules is not table creation.
Form.driver = lambda do |form|
  assert(form.fields.first.options == registry.ids.map { |id| registry.name(id) }, 'Descriptions leaked into another selector')
  form.cancel_button.trigger(:press)
end
assert(app.send(:select_game, 'Rules', registry.ids).nil?, 'Cancelled selector returned a game')

snapshots = %w[uno farkle uno].map { |id| Struct.new(:table).new({'game' => id}) }
lobby = Object.new
queries = 0
lobby.define_singleton_method(:open_table_snapshots) do |hide_inactive:|
  assert(hide_inactive, 'Joining lost inactive-table filtering')
  queries += 1
  snapshots
end
app.instance_variable_set(:@lobby, lobby)
app.define_singleton_method(:run_network_task) { |*, **, &operation| operation.call }
app.define_singleton_method(:show_tables_for_game) { |id| selected = id; true }
Form.driver = lambda do |form|
  list = form.fields.first
  ids = app.send(:ordered_game_ids, snapshots)
  assert(ids.uniq == ids && ids.length == 2, 'Join game list duplicated a game')
  assert(list.options == ids.map { |id| app.send(:game_lobby_label, id) }, 'Join game list does not announce descriptions')
  list.index = ids.index('farkle')
  form.accept_button.trigger(:press)
end
app.send(:show_join_table)
assert(selected == 'farkle' && queries == 1, 'Description changed joining or added a network request')
Form.driver = nil
puts "PASS descriptions: #{registry.ids.length} games / #{languages.length} languages, exact Polish text, create/join/cancel and unchanged other selectors"
