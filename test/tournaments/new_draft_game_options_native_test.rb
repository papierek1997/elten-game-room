ENV['ELTEN_TEST_NATIVE_CONTROLS'] = '1'
require_relative '../support/tournament_native'
require_relative '../support/tournament_entry_context'
require File.join(EltenTestHost.root, 'src/ui/controls/static')
Object.const_set(:Static, EltenAPI::Controls.const_get(:Static)) unless Object.const_defined?(:Static)
require_relative '../../games/catalog'
require_relative '../../lib/tournaments/shared_hub'
require_relative '../support/assertions'
include GameRoomTest::Assertions

GameRoomLocalization.boot(settings: {'interface_language' => 'en', 'known_languages' => ['en']})
label = ->(value) {GameRoomContent.utf8(GameRoomLocalization.translate(value))}
registry = GameRoomGames::CATALOG
game = registry.build('tic_tac_toe')
program = TournamentEntryContextTest::Program.new
alerts, publications = [], []
hub = GameRoomTournaments::SharedHub.new(program: program, registry: registry,
  user: -> {'Alice'}, alert: ->(message) {alerts << message}, confirm: ->(*) {true})
publish = lambda do |**values|
  publications << GameRoomTournaments::Publication.from_draft(registry: registry,
    publication_key: 'native-new-game-options', **values).to_row
  {'status' => 'confirmed'}
end
begin
  editor = GameRoomTournaments::TournamentSetupEditor.new(program: program, registry: registry,
    configure: hub.method(:configure), publish: publish, alert: ->(message) {alerts << message},
    clock: -> {1_800_000_000})
  driver = TournamentNativeDriver.new
  driver.step(label.call('Game'), [13]) { |form| form.fields.first.index = registry.ids.index(game.id) }
  driver.step(nil, [13]) { |form| form.index = form.fields.index(form.accept_button) }
  driver.step(label.call('Tournament name'), [13]) do |form|
    form.fields.first.set_text('Native new-game options')
    form.index = form.fields.index(form.accept_button)
  end
  assert_equal('confirmed', editor.wait&.fetch('status'))
  driver.finish
  assert_equal([], alerts)
  options = JSON.parse(publications.fetch(0).fetch('settings_json')).fetch('game_options')
  assert_equal(1, options['random_start'], 'A new tournament omitted the ordinary random-starter rule')
  players = %w[Alice Bob]
  repository = Struct.new(:players) {def players_for(_session); players; end}.new(players)
  fixed = game.game_start_options(options, players: players, fixed: true)
  opening = game.replay({'options' => JSON.generate(fixed)}, [], repository)
  assert_equal(nil, opening.current_player, 'The fixed new tournament started its first seat without a draw')
  assert(opening.state[:opening_pending], 'The canonical random opening is not pending')

  # Editing an existing publication is not another new-game/default upgrade.
  old_options = game.normalize_options({})
  old_row = publications.fetch(0).merge('settings_json' => JSON.generate(
    JSON.parse(publications.fetch(0)['settings_json']).merge('game_options' => old_options)))
  old_json = old_row.fetch('settings_json').dup
  editor = GameRoomTournaments::TournamentSetupEditor.new(program: program, registry: registry,
    configure: hub.method(:configure), publish: publish, alert: ->(message) {alerts << message},
    clock: -> {1_800_000_000}, publication: old_row)
  driver = TournamentNativeDriver.new
  driver.step(label.call('Tournament name'), [13]) { |form| form.index = form.fields.index(form.accept_button) }
  assert_equal('confirmed', editor.wait&.fetch('status'))
  driver.finish
  assert_equal(old_json, publications.fetch(1)['settings_json'], 'Editing silently upgraded accepted game options')
  assert_equal([], alerts)
  unchanged = game.game_start_options(old_options, players: players, fixed: true)
  assert_equal(old_options, unchanged)
  assert_equal('Alice', game.replay({'options' => JSON.generate(unchanged)}, [], repository).current_player)
ensure
  program.finalize
  program.class.app_runtime.close
end
puts 'PASS new tournament native options: actual selection/configuration/publication/random opening; unchanged existing publication and fixed binding'
