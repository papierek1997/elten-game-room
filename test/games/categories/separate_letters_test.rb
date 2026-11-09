require_relative '../../support/categories'
require_relative '../../support/sequence_random'

game = GameRoomGames::Categories.new
repo = CategoriesRepository.new(%w[Alice Bob])
assert(game.default_options['separate_letters'] == false, 'New variant enabled by default')
%w[pl en].each do |language|
  [1, 6, 9].each do |count|
    options = game.default_options.merge('answer_language'=>language, 'separate_letters'=>true, 'round_category_count'=>count)
    session = {'options'=>JSON.generate(options)}
    context = GameRoomGames::ActionContext.new(now:100, random_source:GameRoomRandom::SequenceSource.new(Array.new(12, 1)))
    before = game.replay(session, [], repo)
    status, plan = game.action_for(game.automatic_action(before, 'Alice', context:context), before, 'Alice', context:context)
    assert(status == :ok, 'Round plan rejected')
    events = []
    append_plan(events, plan, 'Alice')
    assert(events.first['value'].bytesize <= 64, 'Round exceeds native wire limit')
    replay = game.replay(session, events, repo)
    letters = replay.state[:category_letters]
    assert(replay.state[:phase] == :answering && letters.size == count, 'Round assignments missing')
    assert(letters.values.uniq.size == count, 'Categories share a letter')
    assert((letters.values - game.class::LANGUAGE_LETTERS.fetch(language)).empty?, 'Foreign alphabet letter')
    game.surface_spec(replay, 'Bob').fields.each do |field|
      assert(field.label.include?(game.send(:answer_letter_label, letters.fetch(field.id))), 'Answer field uses wrong letter')
    end
    replay.state[:phase] = :review
    replay.state[:reveals] = {'Bob'=>letters.to_h { |category, letter| [category, letter+'answer'] }}
    review = game.send(:review_spec, replay.state)
    review.items.each do |item|
      category = letters.keys.find { |id| item.category.start_with?(game.send(:category_label,id)) }
      assert(category && item.category.include?(game.send(:answer_letter_label, letters.fetch(category))), 'Judge lacks category letter')
    end
    assert(game.shortcut_feature_data(:turn, replay, 'Bob')[:message].include?(review.items.first.category), 'Reminder lost assignments')
    if count > 1
      parts = events.first['value'].split(',')
      [Array.new(count,'A').join('.'), 'A', 'Q.'+letters.values.drop(1).join('.')].each do |wire|
        next if language == 'en' && wire.start_with?('Q.')
        bad = events.first.merge('value'=>parts.each_with_index.map { |value,index| index == 3 ? wire : value }.join(','))
        assert(game.replay(session,[bad],repo).accepted_events.empty?, 'Malformed assignments accepted')
      end
      off_session = {'options'=>JSON.generate(options.merge('separate_letters'=>false))}
      assert(game.replay(off_session, events, repo).accepted_events.empty?, 'Multi-letter wire accepted in ordinary game')
    end
  end
end

# A server round still sends one text-seed recipe, with no local dice calls.
require_relative '../../support/session_runner'
server_round = lambda do |options|
  native = NativeRoomHarness.new(game:game, users:%w[Alice Bob], options:options)
  native.start
  random = Object.new
  def random.roll(**); raise 'Server variant requested local entropy'; end
  context = GameRoomGames::ActionContext.new(random_source:random, server_random:true, table_owner:'Alice', now:1000)
  native.view('Alice').next_random_values = (1..16).to_a
  action = game.automatic_action(native.replay('Alice'), 'Alice', context:context)
  native.submit('Alice', action, context:context)
  native.assert_converged('separate category letters', expected_count:1)
  state = native.replay('Alice').state
  assert(state[:phase] == :answering && state[:category_letters].values.uniq.size == 9, 'Server letters missing')
  assert(native.view('Alice').calls[:random] == 1, 'Per-category server requests')
  state
end

catalog = GameRoomGames::CategoriesCatalog
%w[pl en].product(%w[medium hard]).each do |language, tier|
  options = game.table_creation_options('separate_letters'=>true, 'answer_language'=>language,
    'round_category_count'=>9, 'category_set'=>tier)
  drawn = server_round.call(options).fetch(:round_categories)
  assert(drawn == (catalog::POOLS.fetch(tier) & drawn), 'Server round did not preserve the catalogue order')
  assert((drawn & catalog::BY_DIFFICULTY.fetch('easy')).any?, "#{tier} server round could not draw inherited categories")
  assert((drawn & catalog::BY_DIFFICULTY.fetch(tier)).any?, "#{tier} server round could not draw new categories")
end

# Same server seed and table options as before widening the catalogue.
previous = game.default_options.merge('category_version'=>3, 'category_set'=>'hard',
  'round_category_count'=>9, 'separate_letters'=>true, 'answer_language'=>'en')
old_round = server_round.call(previous)
old_categories = %w[cocktail_name alcohol_brand male_writer screen_character mythological_deity reality_show scientist radio_presenter sewing_material]
assert(old_round.fetch(:round_categories) == old_categories &&
  old_round.fetch(:category_letters) == old_categories.zip(%w[W T M C Y I Q O N]).to_h,
  'Updating the pools changed the interpretation of a previous server seed')
puts 'PASS category letters: local/server rounds, cumulative pools, original seeded replay and validation'
