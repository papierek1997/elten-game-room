require_relative '../../support/game_option_editor_native'

game = GameRoomGames::CashAuction.new
stored = {}
original_read = NativeOptionTest::Program.instance_method(:read_json)
NativeOptionTest::Program.define_method(:read_json) do |path, default:|
  path == 'game_option_preferences.json' ? stored : default
end

begin
  general = {'en'=>['en', 'quiz.general.en'], 'pl'=>['pl-PL', 'quiz.wikidata.pl'],
    'cs'=>['en', 'quiz.general.en'], 'es'=>['en', 'quiz.general.en'], 'ru'=>['ru-RU', 'quiz.general.ru']}
  previous = [[], ['missing'], ['quiz.witcher.books.pl'],
    %w[quiz.harry_potter.books.pl quiz.wikidata.pl quiz.witcher.books.pl]]
  general.each do |ui, (language, pack)|
    NativeOptionTest.language = ui
    previous.each do |ids|
      stored = {'cash_auction'=>{'content_language_id'=>'pl-PL', 'content_pack_ids'=>ids, 'ante'=>10},
        'duck_racing'=>{'question_language'=>'pl-PL', 'question_sets'=>['quiz.witcher.books']}}
      before = Marshal.dump(stored)
      driver = NativeOptionTest::Driver.new(game, creating_table: true)
      NativeOptionTest.assert(driver.control('ante').text == '100', 'New table retained the old ante')
      checklist = driver.control('content_pack_ids')
      definitions = game.effective_option_definitions('content_language_id'=>language)
      choices = definitions.find { |definition| definition.key == 'content_pack_ids' }.choices
      selected = checklist.multiselections.map { |index| choices[index].value }
      NativeOptionTest.assert(selected == [pack], "#{ui}: old checklist changed the default #{selected.inspect}")
      NativeOptionTest.assert(checklist.options == choices.map(&:label), 'A stale unavailable preference reached the new form')
      driver.focus(driver.form.accept_button)
      driver.press([13])
      options = driver.finished.fetch(:game_options)
      NativeOptionTest.assert(options['content_language_id'] == language && options['content_pack_ids'] == [pack], 'Submission restored former sources')
      NativeOptionTest.assert(options['content_pack_manifest'].map { |entry| entry['id'] } == [pack], 'Default source identity was not pinned')
      NativeOptionTest.assert(driver.program.writes.empty? && Marshal.dump(stored) == before, 'Creation changed saved preferences')

      state = GameRoomCashAuction::Rules.initial(%w[Alice Bob], options)
      NativeOptionTest.assert(GameRoomCashAuction::Rules.draw!(state, category:nil, chest:false, now:1000), 'Default auction did not open')
      NativeOptionTest.assert(state[:cash] == [9900, 9900] && state[:pot] == 200, 'Players did not pay the 100-point default ante')
    end
  end

  # Changing a checklist still affects the table being created, but reopening
  # Create ignores that choice. Explicit presets and existing tables keep it.
  NativeOptionTest.language = 'pl'
  driver = NativeOptionTest::Driver.new(game, creating_table: true)
  checklist = driver.focus('content_pack_ids')
  driver.press([36])
  driver.press([32])
  driver.number('ante', 37)
  driver.focus(driver.form.accept_button)
  driver.press([13])
  explicit = driver.finished.fetch(:game_options)
  NativeOptionTest.assert(explicit['content_pack_ids'].length == 2 && explicit['ante'] == 37, 'Manual sources or ante were replaced by defaults')
  NativeOptionTest.assert(driver.program.writes.empty?, 'Manual choices were persisted')
  driver = NativeOptionTest::Driver.new(game, creating_table: true)
  NativeOptionTest.assert(driver.control('content_pack_ids').multiselections.length == 1 && driver.control('ante').text == '100', 'The next creation retained custom choices')
  driver.press([27])
  NativeOptionTest.assert(driver.finished.nil?, 'Cancellation did not return cleanly')
  driver.pristine
  driver = NativeOptionTest::Driver.new(game, initial_options: explicit, submit_label:'Save changes')
  driver.focus(driver.form.accept_button)
  driver.press([13])
  NativeOptionTest.assert(driver.finished == explicit, 'Editing an existing table reset its sources or ante')
  NativeOptionTest.assert(game.game_start_options(explicit, players:%w[Alice Bob], fixed:true) == explicit, 'Fixed tournament settings changed')
ensure
  NativeOptionTest::Program.define_method(:read_json, original_read)
end

puts "Cash Auction defaults: #{NativeOptionTest.checks} native checks of five UI languages, stale checklists, fresh reopen, explicit edits, cancellation and 100-point antes passed."
