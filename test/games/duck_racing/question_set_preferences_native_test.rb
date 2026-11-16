require_relative '../../support/game_option_editor_native'

game = GameRoomGames::DuckRacing.new
challenge_ids = game.option_definitions.find { |definition| definition.key == 'challenges' }.choices.map(&:value).first(3).sort
stored = {}
original_read = NativeOptionTest::Program.instance_method(:read_json)
NativeOptionTest::Program.define_method(:read_json) do |path, default:|
  path == 'game_option_preferences.json' ? stored : default
end

begin
  general = {'en'=>['en', 'quiz.general'], 'pl'=>['pl-PL', 'quiz.wikidata'],
    'cs'=>['en', 'quiz.general'], 'es'=>['en', 'quiz.general'], 'ru'=>['ru-RU', 'quiz.general.ru']}
  previous = [[], ['missing'], ['quiz.witcher.books'], %w[quiz.wikidata quiz.witcher.books]]
  general.each do |ui, (language, set)|
    NativeOptionTest.language = ui
    previous.each do |ids|
      stored = {game.id=>{'question_language'=>'pl-PL', 'question_sets'=>ids, 'challenges'=>challenge_ids}}
      before = Marshal.dump(stored)
      driver = NativeOptionTest::Driver.new(game, creating_table: true)
      definitions = game.effective_option_definitions('question_language'=>language)
      question_choices = definitions.find { |definition| definition.key == 'question_sets' }.choices
      checklist = driver.control('question_sets')
      NativeOptionTest.assert(checklist.options == question_choices.map(&:label), 'A stale question preference reached the form')
      NativeOptionTest.assert(checklist.multiselections.map { |index| question_choices[index].value } == [set], "#{ui}: previous sources replaced the general set")
      driver.focus(driver.form.accept_button)
      driver.press([13])
      options = driver.finished.fetch(:game_options)
      NativeOptionTest.assert(options['question_language'] == language && options['question_sets'] == [set], 'Submitting restored the old sources')
      NativeOptionTest.assert(options['challenges'] == challenge_ids, 'Question defaults reset remembered challenges')
      NativeOptionTest.assert(driver.program.writes.last[1].fetch(game.id) == {'challenges'=>challenge_ids}, 'Question choices were persisted again')
      NativeOptionTest.assert(Marshal.dump(stored) == before, 'Reading defaults mutated the saved document')
    end
  end

  NativeOptionTest.language = 'pl'
  driver = NativeOptionTest::Driver.new(game, creating_table: true)
  checklist = driver.focus('question_sets')
  driver.press([35])
  driver.press([32])
  driver.focus(driver.form.accept_button)
  driver.press([13])
  explicit = driver.finished.fetch(:game_options)
  NativeOptionTest.assert(explicit['question_sets'].length == 2, 'Manual specialist selection was discarded')
  NativeOptionTest.assert(driver.program.writes.last[1].fetch(game.id).keys == ['challenges'], 'Creating a table remembered its sources')
  driver = NativeOptionTest::Driver.new(game, creating_table: true)
  NativeOptionTest.assert(driver.control('question_sets').multiselections.length == 1, 'Reopening retained the prior custom sets')
  driver.press([27])
  NativeOptionTest.assert(driver.finished.nil?, 'Cancel did not return cleanly')
  driver.pristine
  driver = NativeOptionTest::Driver.new(game, initial_options: explicit, submit_label:'Save changes')
  NativeOptionTest.assert(driver.control('question_sets').multiselections.length == 2, 'Editing lost existing sources')
  driver.focus(driver.form.accept_button)
  driver.press([13])
  NativeOptionTest.assert(driver.finished == explicit, 'Explicit table options changed')
  NativeOptionTest.assert(game.game_start_options(explicit, players:%w[Alice Bob], fixed:true) == explicit, 'Fixed tournament questions changed')
ensure
  NativeOptionTest::Program.define_method(:read_json, original_read)
end

puts "Duck Racing question defaults: #{NativeOptionTest.checks} native checks of five languages, stale/empty choices, challenge persistence, reopening, cancellation and explicit table settings passed."
