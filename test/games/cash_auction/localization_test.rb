require_relative '../../support/game_option_encoding'

app = EltenGameRoom.allocate
app.define_singleton_method(:read_json) { |_path, default:| default }
app.define_singleton_method(:remember_multiple_choice_options) { |*_arguments| }
app.define_singleton_method(:alert) { |message| raise message }
checks = {forms: 0, checkbox_states: 0, labels: 0}
Form.option_encoding_driver = GameOptionEncodingFixture.driver(checks)
%w[en pl cs es ru].each do |language|
  $option_host_language = 'ru'
  GameRoomTestLocalization.use_language(language)
  game = EltenGameRoom::GAME_REGISTRY.build('cash_auction')
  raise 'Auction missing from catalog' unless game
  options = app.send(:configure_game_options, game)
  raise 'Auction defaults changed on focus' unless options == game.table_creation_options
  raise 'Wrong published defaults' unless options.values_at('starting_points', 'ante', 'pass_penalty', 'rounds', 'count_interval', 'black_chest_chance') == [10_000, 100, 200, 8, 3, 10]
  penalty = game.effective_option_definitions(options).find { |definition| definition.key == 'pass_penalty' }
  raise 'The fixed percentage penalty is editable' if game.option_visible?(penalty, options)
  raise 'The fixed penalty changed across languages' unless GameRoomCashAuction::Rules.inactivity_penalty(
    GameRoomCashAuction::Rules.initial(%w[Alice Bob], options), 0) == 500
  book = game.rule_book
  authored = JSON.parse(File.read(File.expand_path("../../../tools/data/rulebooks/#{language.upcase}/cash_auction.json", __dir__), encoding: 'UTF-8'))
  authored.fetch('sections').each do |expected|
    actual = book.sections.find { |section| section.id.to_s == expected.fetch('id') }
    raise 'Missing generated auction chapter' unless actual
    raise 'Title differs from reviewed source' unless actual.title == expected.fetch('title').fetch(language)
    raise 'Paragraphs differ from reviewed source' unless actual.paragraphs == expected.fetch('paragraphs').map { |paragraph| paragraph.fetch(language) }
  end
  schemas = game.effective_option_definitions(options)
  keys = schemas.map(&:key).uniq - ['bot_delay']
  raise 'An auction setting lacks rulebook help' unless authored['option_chapters'].keys.sort == keys.sort
  state = GameRoomCashAuction::Rules.initial(%w[Alice Bob], options).merge(game_id: 'locale-auction')
  GameRoomCashAuction::Rules.draw!(state, category: 0, chest: false, now: 1000)
  replay = GameRoomGames::Replay.new(players: state[:players], state: state, history: [], accepted_events: [])
  surface = GameSurfaces.build(game.surface_spec(replay, 'Alice'))
  raise 'Auction retained a withdrawal button' unless surface.fields.length == 1
  surface.fields.each do |field|
    text = field.respond_to?(:label) ? field.label : field.header
    raise 'Binary auction field is not UTF-8' unless text.encoding == Encoding::UTF_8 && text.valid_encoding?
    text + ' — Заżółć'
    field.focus
  end
  opening = GameRoomCashAuction::Rules.initial(%w[Alice Bob], options)
  opening.merge!(phase: :opening_chests, chests: [1, 0], chest_base_cash: opening[:cash].dup,
    chest_percentages: [0, 0], open_chests_at: 5)
  before = {phase: :opening_chests, eliminated: [false, false], question_target: opening[:question_target]}
  raise 'Automatic localized opening failed' unless GameRoomCashAuction::Rules.open_chests!(opening,
    random_source: Random.new(1), now: 5)
  entries = game.send(:auction_event_history, {'action'=>'open_chests'}, 'Alice', 1, opening, before, nil)
  expected = {'en'=>'Opening the black chests!', 'pl'=>'Otwieramy czarne skrzynki!',
    'cs'=>'Otevíráme černé truhly!', 'es'=>'¡Abrimos los cofres negros!',
    'ru'=>'Открываем чёрные сундуки!'}
  raise 'Chest introduction was not translated' unless entries.first.text == expected.fetch(language)
  raise 'Percentage was lost from the contents' unless entries.any? { |entry| entry.text.include?('+') && entry.text.include?('%') }
  entries.each do |entry|
    raise 'Binary chest message has invalid encoding' unless entry.text.encoding == Encoding::UTF_8 && entry.text.valid_encoding?
  end
end
raise 'Polish title is missing' unless RULES_CATALOG['Cash Auction'] == 'Awantura o kasę'
puts 'Cash Auction binary localization: five native option forms, all published defaults, complete reviewed rulebooks, option help, Unicode bid controls without withdrawal and Polish catalog title passed.'
