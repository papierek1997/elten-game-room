require_relative '../../lib/game_room_preferences'
require_relative '../support/assertions'
include GameRoomTest::Assertions

%w[Alice aLiCe first_last User123].each do |account|
  assert_equal(account, GameRoomParticipants.display_name(account))
end
%i[configure_display_name remember_display_name custom_display_name local_display_name
  normalize_display_name scoped_display_name metadata_display_name short_name shorten_announcement names_revision].each do |method|
  assert(!GameRoomParticipants.respond_to?(method), "Retired name API remains: #{method}")
end
['Anna Kowalska', "invalid\nname", 'x' * 300, nil].each do |value|
  source = {'display_name'=>value, 'invitation_notifications'=>'contacts', 'game_sounds'=>false}
  normalized = GameRoomPreferences.normalize(source, [])
  assert(!normalized.key?('display_name'), 'An old alias survived settings normalization')
  assert_equal('contacts', normalized['invitation_notifications'])
  assert_equal(false, normalized['game_sounds'])
  assert_equal(value, source['display_name'], 'Normalization mutated the source')
end
bot = GameRoomParticipants.bot_id(1, 7)
assert_equal('Computer 7', GameRoomParticipants.display_name(bot))
named = GameRoomParticipants.bots_for(1, 1, names: ['pl01']).first
assert_equal(GameRoomBotNames.name_for('pl01'), GameRoomParticipants.display_name(named))
puts 'PASS account names stay literal; retired alias APIs/defaults removed, old preferences discarded, bot names retained'
