require_relative '../../support/game_option_editor_native'

NativeOptionTest.language = 'en'
game = GameRoomGames::CashAuction.new
pl = game.table_creation_options('content_language_id'=>'pl-PL')
general = pl.fetch('content_pack_ids')
NativeOptionTest.assert(general == ['quiz.wikidata.pl'], 'Polish defaults selected specialist topics')
ids = game.effective_option_definitions(pl).find { |definition| definition.key == 'content_pack_ids' }.choices.map(&:value)
NativeOptionTest.assert(ids.length == 3, 'The real Polish catalog lost its three question sets')
pl = game.table_creation_options(pl.merge('content_pack_ids'=>ids))

# The actual ListBox handles Space, and submit derives the manifest from the
# resulting IDs instead of retaining the former three-pack identity.
driver = NativeOptionTest::Driver.new(game, initial_options: pl)
NativeOptionTest.assert(!driver.visible?('pass_penalty'), 'A current table can edit the fixed 5% penalty')
sets = driver.focus('content_pack_ids')
NativeOptionTest.assert(sets.multiselections == [0, 1, 2], 'Three-pack defaults were not checked')
driver.press([36])
driver.press([32])
NativeOptionTest.assert(sets.multiselections == [1, 2], 'Space did not clear one question set')
driver.focus(driver.form.accept_button)
driver.press([13])
two = driver.finished
NativeOptionTest.assert(two['content_pack_ids'] == ids.drop(1), 'Native save changed pack IDs')
NativeOptionTest.assert(two['content_pack_manifest'].map { |entry| entry['id'] } == ids.drop(1), 'Native save retained a stale pack manifest')
NativeOptionTest.assert(pl['content_pack_manifest'].map { |entry| entry['id'] } == ids, 'Native editing changed its input')

# An empty choice keeps the same form and controls. The player can choose
# just one set and submit again without adding unrelated topics.
driver = NativeOptionTest::Driver.new(game, initial_options: two)
sets = driver.focus('content_pack_ids')
driver.press([35])
driver.press([32])
driver.press([38])
driver.press([32])
driver.focus(driver.form.accept_button)
driver.press([13])
NativeOptionTest.assert(driver.program.alerts.last.to_s.include?('Choose from 1 to 3'), 'The empty-set refusal did not explain the required count')
NativeOptionTest.assert(sets.multiselections.empty?, 'Validation reset the unfinished checklist')
driver.pristine
driver.focus(sets)
driver.press([32])
driver.focus(driver.form.accept_button)
driver.press([13])
one = driver.finished
NativeOptionTest.assert(one['content_pack_ids'] == general, 'A repaired single-set choice was refused or changed')
NativeOptionTest.assert(one['content_pack_manifest'].map { |entry| entry['id'] } == general, 'One-set save retained the former manifest')
NativeOptionTest.assert(one.reject { |key, _| %w[content_pack_ids content_pack_manifest].include?(key) } == two.reject { |key, _| %w[content_pack_ids content_pack_manifest].include?(key) }, 'Repairing the checklist changed unrelated options')

# Language changes replace dependent choices in place. The native focus stays
# on Language, and EN's allowed single set has the correct pinned identity.
driver = NativeOptionTest::Driver.new(game, initial_options: pl)
sets = driver.control('content_pack_ids')
language = driver.focus('content_language_id')
driver.press([36])
NativeOptionTest.assert(driver.form.fields[driver.form.index].equal?(language), 'Changing language stole focus')
NativeOptionTest.assert(sets.options.length == 1 && sets.multiselections == [0], 'English did not select its sole pack')
driver.pristine
driver.focus(driver.form.accept_button)
driver.press([13])
english = driver.finished
NativeOptionTest.assert(english['content_language_id'] == 'en', 'Language selection was lost')
NativeOptionTest.assert(english['content_pack_ids'] == ['quiz.general.en'], 'English inherited Polish pack IDs')
NativeOptionTest.assert(english['content_pack_manifest'].map { |entry| entry['id'] } == ['quiz.general.en'], 'English retained a Polish manifest')

driver = NativeOptionTest::Driver.new(game, initial_options: english)
sets = driver.control('content_pack_ids')
language = driver.focus('content_language_id')
driver.press([40])
NativeOptionTest.assert(driver.form.fields[driver.form.index].equal?(language), 'Refreshing Polish choices stole focus')
NativeOptionTest.assert(sets.options.length == 3 && sets.multiselections == [ids.index(general.first)], 'Polish did not select only its general set')
driver.focus(sets)
driver.press([36])
driver.press([32])
driver.press([27])
NativeOptionTest.assert(driver.finished.nil? && driver.program.writes.empty?, 'Cancel stored changed question sources')
NativeOptionTest.assert(english['content_pack_ids'] == ['quiz.general.en'], 'Cancel changed the original options')

# A manual language choice is valid for this table, but saving it must not
# persist the question checklist or override the next table's UI defaults.
driver = NativeOptionTest::Driver.new(game)
language = driver.focus('content_language_id')
driver.press([36])
driver.press([40])
driver.focus(driver.form.accept_button)
driver.press([13])
saved = driver.finished
NativeOptionTest.assert(saved['content_language_id'] == 'pl-PL' && saved['content_pack_ids'] == general, 'The manual table language lost its general set')
NativeOptionTest.assert(driver.program.writes.empty?, 'Creating Cash Auction persisted the question checklist')

missing = pl.merge('content_pack_ids'=>['missing'])
driver = NativeOptionTest::Driver.new(game, initial_options: missing)
sets = driver.control('content_pack_ids')
NativeOptionTest.assert(sets.options.last == 'Unavailable choice: missing' && sets.multiselections == [3], 'An unavailable source was silently hidden')
driver.focus(driver.form.accept_button)
driver.press([13])
NativeOptionTest.assert(driver.program.alerts.last.to_s.include?('not installed'), 'An unavailable source passed validation')
driver.pristine
driver.press([27])
NativeOptionTest.assert(driver.finished.nil?, 'The invalid-options form could not be cancelled')

puts "Cash Auction native source editor: #{NativeOptionTest.checks} checks of Space/Enter/Escape, one/two/three sets, empty validation repair, general defaults, language focus, pinned manifests and cancellation passed."
