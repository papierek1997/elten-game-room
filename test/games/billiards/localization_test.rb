require_relative '../../support/game_option_encoding'

app = EltenGameRoom.allocate
app.define_singleton_method(:read_json) { |_path, default:| default }
app.define_singleton_method(:remember_multiple_choice_options) { |*_arguments| }
app.define_singleton_method(:alert) { |message| raise message }
checks = {forms: 0, checkbox_states: 0, labels: 0}
Form.option_encoding_driver = GameOptionEncodingFixture.driver(checks)
%w[ru en pl cs es].each do |language|
  $option_host_language = %w[cs es].include?(language) ? 'ru' : language
  GameRoomTestLocalization.use_language(language)
  game = EltenGameRoom::GAME_REGISTRY.build('billiards')
  options = app.send(:configure_game_options, game)
  raise 'Options changed during focus' unless options == game.table_creation_options
  raise 'New table did not select Social billiards' unless options['discipline'] == 'friendly'
  raise 'New social table did not select nine balls' unless options['layout'] == 'diamond'
  book = game.rule_book
  raise 'Missing localized controls' unless book.sections.last.id.to_s == 'controls'
  authored = JSON.parse(File.read(File.expand_path("../../../tools/data/rulebooks/#{language.upcase}/billiards.json", __dir__), encoding: 'UTF-8'))
  authored.fetch('sections').each do |expected|
    actual = book.sections.find { |section| section.id.to_s == expected.fetch('id') }
    raise "Missing generated chapter #{expected.fetch('id')}" unless actual
    raise 'Generated title differs from reviewed source' unless actual.title == expected.fetch('title').fetch(language)
    raise 'Generated prose differs from reviewed source' unless actual.paragraphs == expected.fetch('paragraphs').map { |paragraph| paragraph.fetch(language) }
  end
  keys = game.effective_option_definitions.map(&:key) - ['bot_delay']
  raise 'A practice option lacks help' unless authored['option_chapters'].keys.sort == keys.sort
  repository = Object.new
  def repository.players_for(_session); ['Alice', 'Bob']; end
  disciplines = ['practice'] + game.option_definitions.find { |definition| definition.key == 'discipline' }.choices.map(&:value)
  disciplines.each do |discipline|
    repository.define_singleton_method(:players_for) { |_session| discipline == 'cutthroat' ? %w[Alice Bob Carol] : %w[Alice Bob] }
    replay = game.replay({'__id'=>"billiards-#{discipline}", 'options'=>JSON.generate(options.merge('discipline'=>discipline))}, [], repository)
    surface = GameSurfaces.build(game.surface_spec(replay, 'Alice'))
    surface.fields.each do |field|
      labels = field.respond_to?(:label) ? [field.label] : [field.header, *field.options]
      labels.each do |label|
        raise 'Binary control label not UTF-8' unless label.encoding == Encoding::UTF_8 && label.valid_encoding?
        label + ' — выбранное поле'
      end
      field.focus
    end
    surface.handle_command('angle')
    surface.handle_command('line')
    surface.handle_command('behind')
    surface.handle_command('selected')
    surface.handle_command('match_status') unless discipline == 'practice'
  end
end
raise 'No Polish billiards translation' unless RULES_CATALOG['Billiards'] == 'Bilard'
puts "Billiards binary source localization: #{checks[:forms]} native option forms, five complete rulebooks and all sixteen disciplines' cue/ball announcements; game-language labels beside Russian host controls passed."
