require_relative '../../support/game_option_editor_native'
game = GameRoomGames::Poker.new
driver = NativeOptionTest::Driver.new(game, creating_table:true)
NativeOptionTest.assert(!driver.visible?('big_blind'), 'Big blind remains an editable field')
driver.number('small_blind', 50)
driver.press([13]) # Submit directly from the numeric field, without a list move.
options = driver.finished.fetch(:game_options)
NativeOptionTest.assert(options.values_at('small_blind', 'big_blind') == [50,100], 'Small blind did not derive twice the big blind')
NativeOptionTest.assert(driver.program.alerts.empty?, 'Derived blinds raised a validation error')

driver = NativeOptionTest::Driver.new(game, initial_options:options)
driver.number('small_blind', 25)
driver.focus(driver.form.accept_button)
driver.press([13])
NativeOptionTest.assert(driver.finished.values_at('small_blind','big_blind') == [25,50], 'Editing left a stale large blind')
driver = NativeOptionTest::Driver.new(game, initial_options:options)
driver.number('small_blind', 7)
driver.press([27])
NativeOptionTest.assert(driver.finished.nil? && options['small_blind'] == 50, 'Cancel changed the original options')

old = game.normalize_options('small_blind'=>50, 'big_blind'=>75)
NativeOptionTest.assert(old['big_blind'] == 75, 'Cold replay rewrote an existing hand')
driver = NativeOptionTest::Driver.new(game, initial_options:old)
driver.focus(driver.form.accept_button)
driver.press([13])
NativeOptionTest.assert(driver.finished['big_blind'] == 100, 'Editor retained an obsolete separately set big blind')
NativeOptionTest.assert(game.new_game_options(old)['big_blind'] == 100, 'New-game preparation retained a separately set big blind')
NativeOptionTest.assert(game.game_start_options(old, players:%w[A B], fixed:true)['big_blind'] == 75, 'Fixed tournament identity changed')
ante = game.normalize_options('variant'=>'draw','draw_uses_blinds'=>false,'small_blind'=>0,'big_blind'=>10)
NativeOptionTest.assert(game.new_game_options(ante)['big_blind'] == 10, 'Unused small blind changed the ante game minimum raise')
NativeOptionTest.assert(game.option_editor_changes(ante,ante).empty?, 'Hidden ante-game fields were changed by the editor')
puts 'PASS native Poker options: one visible blind, direct Enter/Save, edits, cancel, new game and immutable fixed settings'
