require_relative '../../lib/game_participants'
require_relative '../../lib/game_room_preferences'

def check(value, message)
  raise message unless value
end

names = GameRoomParticipants
names.configure_display_name(account: 'login97', name: '  Anna   Kowalska  ')
check(names.display_name('LOGIN97') == 'Anna Kowalska', 'full display name or case-insensitive lookup lost')
check(names.short_name('login97') == 'Anna', 'live name is not the first name')
check(names.same?('login97', 'LOGIN97') && !names.same?('login97', 'Anna Kowalska'), 'alias became identity')
check(names.display_name('unknown_user') == 'unknown_user' && names.short_name('unknown_user') == 'unknown_user', 'unknown login was shortened')
check(names.local_display_name == 'Anna Kowalska', 'local published preference not normalized')
revision = names.names_revision
names.remember_display_name('LOGIN97', 'Anna Kowalska')
check(names.names_revision == revision, 'unchanged label invalidated presentation')
names.configure_display_name(account: 'login97', name: '')
check(names.display_name('login97') == 'login97', 'empty preference did not restore login')
check(names.normalize_display_name("Anna\nKowalska").nil? && names.normalize_display_name('x' * 65).nil?, 'invalid name admitted')
check(names.normalize_display_name('Ż' * 64) == 'Ż' * 64, 'Unicode name rejected')
check(names.normalize_display_name(' Żaneta Kowalska '.b) == 'Żaneta Kowalska', 'binary-loaded UTF-8 name rejected')
check(names.normalize_display_name("\u00a0Anna\u00a0") == 'Anna', 'Unicode whitespace was not trimmed')
check(GameRoomPreferences.normalize({'display_name' => ' Anna  Kowalska '}, [])['display_name'] == 'Anna Kowalska', 'settings lost name')
names.remember_display_name('login97', 'Anna Kowalska')
names.remember_display_name('other', 'Jan Nowak')
text = 'Anna Kowalska moves. Jan Nowak answers: Anna Kowalska. xAnna Kowalska2.'
spoken = names.shorten_announcement(text, participants: %w[login97 other], protected_texts: ['answers: Anna Kowalska'])
check(spoken == 'Anna moves. Jan answers: Anna Kowalska. xAnna Kowalska2.', 'shortening changed protected text or word fragments')
check(text.start_with?('Anna Kowalska'), 'shortening mutated canonical history')
bot = names.bot_id(1, 1)
check(names.short_name(bot) == names.display_name(bot), 'computer number removed')
names.configure_display_name(account: 'different-account', name: '')
check(names.display_name('login97') == 'login97', 'names leaked across local account switch')
4097.times { |i| names.remember_display_name("person#{i}", "Name #{i}") }
check(names.display_name('person0') == 'person0' && names.display_name('person4096') == 'Name 4096', 'directory count is unbounded or evicts new names')
names.configure_display_name(account: 'owner', name: 'Owner Name')
4097.times { |i| names.remember_display_name("remote#{i}", "Name #{i}") }
check(names.display_name('owner') == 'Owner Name', 'cache eviction hid the local preference')
other_runtime = Module.new.extend(GameRoomParticipantNames)
check(other_runtime.custom_display_name('remote4096').nil?, 'directory state leaked between Runtime namespaces')
puts 'PASS display names: full/short/fallback, immutable identity, Unicode, protected live text, account scope and bounded cache'
