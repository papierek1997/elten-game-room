require_relative '../support/binary_rules_load' if ARGV.first
require_relative '../support/ui'
require_relative '../support/tournament_public_ui'
require_relative '../../lib/tournaments/tournament_setup_editor'
require_relative '../support/assertions'
include GameRoomTest::Assertions
GameRoomLocalization.boot(settings:{'interface_language'=>'en','known_languages'=>['en']})
Form.prepend(TournamentPublicUI::Script)
u=TournamentPublicUI
cases=[['three_five_eight',{},[3]],['spades',{'team_size'=>0},[3,4,5,6]],
  ['spades',{'team_size'=>2},[4,6]],['spades',{'team_size'=>3},[]],['audio_ball',{},[2]]]
cases.each do |id,options,counts|
  editor=GameRoomTournaments::TournamentSetupEditor.new(program:Object.new,registry:GameRoomGames::CATALOG,
    configure:->(game,previous){game.normalize_options(previous.merge(options))},publish:->(**){raise 'Cancelled setup published'},alert:->(message){raise message})
  u.script(->(form){game=u.field(form,'Game');game.index=GameRoomGames::CATALOG.ids.index(id);game.trigger(:select)},
    ->(form){
      seats=u.field(form,'Players per match')
      assert_equal(counts.map(&:to_s),seats.options,"#{id}: invalid choices at initial form entry")
      assert_equal(counts.size==1,form.instance_variable_get(:@hidden_controls).include?(seats),"#{id}: fixed count visibility wrong")
      assert_equal(counts,editor.instance_variable_get(:@seat_counts))
      form.cancel_button.trigger(:press)
    }){editor.wait}
end
future=Class.new(GameRoomGames::ThreeFiveEight) do
  def id; 'future_three_seat_game'; end
end
registry=GameRoomGames::Registry.new([future])
editor=GameRoomTournaments::TournamentSetupEditor.new(program:Object.new,registry:registry,
  configure:->(_game,options){options},publish:->(**){raise 'Cancelled future game published'},alert:->(message){raise message})
u.script(->(form){u.field(form,'Game').trigger(:select)},->(form){
  seats=u.field(form,'Players per match')
  assert_equal(['3'],seats.options)
  assert(form.instance_variable_get(:@hidden_controls).include?(seats),'New game requires an identifier allowlist')
  form.cancel_button.trigger(:press)
}){editor.wait}
puts 'PASS immediate game-specific match sizes: 3-5-8 fixed three, public Spades individual/pairs only, Audio Ball fixed two, fixed choices hidden'
