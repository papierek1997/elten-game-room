require_relative '../support/tournament_individual_ui'
require_relative '../support/tournament_window_fields'
require_relative '../../lib/tournaments/tournament_setup_editor'
include GameRoomTest::Assertions
I = TournamentIndividualUI
T = GameRoomTournaments
GameRoomLocalization.boot(settings:{'interface_language'=>'en', 'known_languages'=>['en']})
fixture = I.fixture
saved = []
begin
  [false, true].each do |publish|
    driver = TournamentNativeDriver.new
    driver.step('Game', [13]) { |form| form.fields.first.index = GameRoomGames::CATALOG.ids.index('taboo') }
    driver.step('Tournament name', [publish ? 13 : 27]) do |form|
      seats = I::F.field(form, 'Players per match')
      assert_equal(['4'], seats.options, 'Native public setup offered an unplayable team size')
      I::F.field(form, 'Tournament name').set_text('Public Taboo pairs')
      form.index = form.fields.index(form.accept_button) if publish
    end
    T::TournamentSetupEditor.new(program:fixture[:program], registry:GameRoomGames::CATALOG,
      configure:->(_game, options){ options }, alert:->(message){ raise message },
      clock:-> { Time.local(2026,11,11,15).to_i },
      publish:->(**values){ saved << values; {'status'=>'confirmed'} }).wait
    driver.finish
    assert_equal(publish ? 1 : 0, saved.size, 'Cancellation unexpectedly requested publication')
  end
  assert_equal(4, saved.first[:draft]['players_per_match'])
ensure
  fixture[:program].finalize
  fixture[:program].class.app_runtime.close
end
puts 'PASS native public Taboo setup: supported four-seat pairs only, normal cancellation and publication'
