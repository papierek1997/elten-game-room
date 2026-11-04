require_relative '../../support/host_source'
require_relative '../../support/game_room_language_runtime'
require_relative '../../support/assertions'

include GameRoomTest::Assertions
GameRoomLanguageRuntime.load_host(EltenTestHost.root)
root = GameRoomLanguageRuntime::ROOT
catalogs = %w[pl cs es ru].to_h { |code| [code, File.binread(File.join(root, "locale/#{code.upcase}.mo"))] }
expected = {
  'en' => ['Enter confirms the assessment.', 'Assessed.', 'Tournament games cannot be saved or resumed from a saved game.'],
  'pl' => ['Enter zatwierdza ocenę.', 'Oceniono.', 'Partii turniejowych nie można zapisywać ani wznawiać z zapisu.'],
  'cs' => ['Enter potvrdí hodnocení.', 'Ohodnoceno.', 'Turnajové hry nelze ukládat ani obnovovat z uložené hry.'],
  'es' => ['Enter confirma la valoración.', 'Valoración guardada.', 'Las partidas de torneo no se pueden guardar ni reanudar desde una partida guardada.'],
  'ru' => ['Enter подтверждает оценку.', 'Оценено.', 'Турнирные партии нельзя сохранять или возобновлять из сохранённой игры.']
}
repository = Object.new
def repository.actor_of(event); event.fetch('actor'); end
def repository.event_id(event); event.fetch('id'); end
event = {'id' => 1, 'actor' => 'Alice', 'action' => 'review_unique'}

GameRoomLanguageRuntime.protect_host do
  expected.each do |language, texts|
    runtime = GameRoomLanguageRuntime::Runtime.new(settings: {'interface_language' => language}, catalogs: catalogs).start
    game = runtime.namespace::GameRoomGames::Categories.new
    state = {phase: :review, options: game.default_options, category_letters: {}, round: 1, attempt: 1, roster_revision: 0,
      players: %w[Alice Bob], judge: 'Alice', active_players: ['Bob'], round_player_order: ['Bob'],
      round_categories: ['country'], reveals: {'Bob' => {'country' => 'Austria'}}, decisions: {}, letter: 'A'}
    spec = game.send(:review_spec, state)
    surface = runtime.namespace::GameSurfaces.build(spec)
    assert_equal(texts[0], spec.confirmation_hint)
    assert(surface.fields[1].header.include?(texts[0]))
    entry = Struct.new(:event_id, :kind, :text).new(1, :review, 'Canonical review')
    replay = runtime.namespace::GameRoomGames::Replay.new(state: state, history: [entry], accepted_events: [event])
    assert_equal([texts[1]], game.describe_event(event, repository, replay, 'Alice'))
    assert_equal(['Canonical review'], game.describe_event(event, repository, replay, 'Bob'))
    assert_equal(texts[2], runtime.namespace::GameRoomLocalization.translate(expected['en'][2]))
    [spec.confirmation_hint, surface.fields[1].header, *game.describe_event(event, repository, replay, 'Alice')].each do |text|
      assert(text.encoding == Encoding::UTF_8 && text.valid_encoding?, "#{language}: invalid binary-source review text")
    end
    assert_equal([Encoding::ASCII_8BIT], runtime.source_encodings.uniq)
  end
end
puts 'PASS Categories review and tournament-save feedback: five actual binary-loaded language runtimes, compiled catalogs and untouched host locale'
