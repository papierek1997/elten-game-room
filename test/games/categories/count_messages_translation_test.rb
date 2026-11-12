require_relative '../../support/host_source'
require_relative '../../support/game_room_language_runtime'
require_relative '../../support/assertions'

include GameRoomTest::Assertions
GameRoomLanguageRuntime.load_host(EltenTestHost.root)
catalogs = %w[pl cs es ru].to_h do |code|
  [code, File.binread(File.join(GameRoomLanguageRuntime::ROOT, "locale/#{code.upcase}.mo"))]
end
expected = {
  'en' => {categories: ['1 category per round', '2 categories per round', '5 categories per round'],
    points: ['Bob scored 0 points in this round.', 'Bob scored 1 point in this round.',
      'Bob scored 2 points in this round.', 'Bob scored 4 points in this round.'], target: '22 points'},
  'pl' => {categories: ['1 kategoria na rundę', '2 kategorie na rundę', '5 kategorii na rundę'],
    points: ['Bob zdobywa w tej rundzie 0 punktów.', 'Bob zdobywa w tej rundzie 1 punkt.',
      'Bob zdobywa w tej rundzie 2 punkty.', 'Bob zdobywa w tej rundzie 4 punkty.'], target: '22 punkty'},
  'cs' => {categories: ['1 kategorie v každém kole', '2 kategorie v každém kole', '5 kategorií v každém kole'],
    points: ['Bob: 0 bodů v tomto kole.', 'Bob: 1 bod v tomto kole.',
      'Bob: 2 body v tomto kole.', 'Bob: 4 body v tomto kole.'], target: '22 bodů'},
  'es' => {categories: ['1 categoría por ronda', '2 categorías por ronda', '5 categorías por ronda'],
    points: ['Bob ha conseguido 0 puntos en esta ronda.', 'Bob ha conseguido 1 punto en esta ronda.',
      'Bob ha conseguido 2 puntos en esta ronda.', 'Bob ha conseguido 4 puntos en esta ronda.'], target: '22 puntos'},
  'ru' => {categories: ['1 категория за раунд', '2 категории за раунд', '5 категорий за раунд'],
    points: ['Bob: 0 очков за этот раунд.', 'Bob: 1 очко за этот раунд.',
      'Bob: 2 очка за этот раунд.', 'Bob: 4 очка за этот раунд.'], target: '22 очка'}
}

GameRoomLanguageRuntime.protect_host do
  expected.each do |language, texts|
    runtime = GameRoomLanguageRuntime::Runtime.new(settings: {'interface_language' => language}, catalogs: catalogs).start
    game = runtime.namespace::GameRoomGames::Categories.new
    [1, 2, 5].zip(texts[:categories]).each do |count, phrase|
      summary = game.options_summary(game.default_options.merge('round_category_count' => count, 'target_score' => 22))
      assert(summary.include?(phrase), "#{language}: wrong category-count form: #{summary}")
      assert(summary.include?(texts[:target]), "#{language}: wrong target-score form: #{summary}")
      assert(summary.encoding == Encoding::UTF_8 && summary.valid_encoding?, 'Binary summary reached the native UI')
    end
    [0, 1, 2, 4].zip(texts[:points]).each do |points, message|
      state = game.send(:initial_state, %w[Alice Bob], game.default_options)
      state.merge!(phase: :review, round: 1, attempt: 1, judge: 'Alice', active_players: ['Bob'],
        round_player_order: ['Bob'], round_categories: %w[country city],
        reveals: {'Bob' => {'country' => 'Austria', 'city' => 'Athens'}}, review_finished: true)
      decisions = points == 4 ? %w[unique unique] : [points == 2 ? 'unique' : points == 1 ? 'partial' : 'incorrect', 'incorrect']
      state[:decisions] = game.send(:review_items, state).zip(decisions).to_h { |item, decision| [item[:id], decision] }
      frame = runtime.namespace::GameRoomReduction::Frame.new(state: state, players: state[:players],
        options: state[:options], history: [])
      input = runtime.namespace::GameRoomReduction::Event.new(action: 'round_score', actor: 'Alice', id: 7, value: "0,#{points}")
      assert(game.send(:reduce_round_score, frame, input), 'Real score reducer refused the assessed points')
      assert_equal(points, state[:scores]['Bob'], 'Message correction changed scoring')
      assert_equal([message], frame.history.map(&:text), "#{language}: score announcement")
      assert(frame.history.first.text.encoding == Encoding::UTF_8 && frame.history.first.text.valid_encoding?,
        'Binary score text reached the native UI')
    end
  end
end

puts 'PASS Categories counts: five binary-loaded languages, category/target plurals, actual 0/1/2/4-point reductions and unchanged scoring'
