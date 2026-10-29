require_relative "../../support/binary_rule_dictionary"
require_relative "../../support/krowa_sjp_html"
require "tmpdir"
BinaryRulesLoad.load(File.join(BinaryRulesLoad::ROOT, "games/krowa_support/client.rb"))

class KrowaBinaryStorage
  def initialize
    @data = {}
    directory = @directory = Dir.mktmpdir("krowa-binary-hidden-")
    at_exit { FileUtils.remove_entry(directory) if File.directory?(directory) }
  end
  def data_path(name); File.join(@directory, name); end
  def read_json(path, default:); @data.fetch(path, default); end
  def write_json(path, value); @data[path] = value; true; end
  def update_json(path, default:); value = read_json(path, default: default); yield value; write_json(path, value); value; end
end
repo = GameRoomSavedGameArchive::ReplayRepository.new
bank = GameRoomGames::KrowaWordBank.new(GameRoomKrowa::WordRepository.new(%w[żółć łapa koza]))
game = GameRoomGames::Krowa.new(bank: bank)
random = Object.new
random.define_singleton_method(:roll) { |count:, sides:| Struct.new(:values).new(Array.new(count, 1)) }
windows = 0
%w[pl en fallback].each do |language|
  $rules_english = language != "pl"
  GameRoomTestLocalization.use_language(language)
  %w[random race tower].each do |variant|
    players = variant == "random" ? ["Żaneta"] : ["Żaneta", "Michał"]
    options = game.default_options.merge("variant" => variant, "length" => 4)
    session = {"__id" => 41, "__players" => players, "options" => JSON.generate(options)}
    storage = KrowaBinaryStorage.new
    context = GameRoomGames::ActionContext.new(session_id: 41, table_id: 9, table_owner: players.first,
      now: 1_800_000_000.25, random_source: random,
      hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::ProgramStorage.new(storage)))
    replay = game.replay(session, [], repo)
    selection = game.automatic_action(replay, players.first, context: context)
    status, plan = game.action_for(selection, replay, players.first, context: context)
    raise "Binary prepare failed" unless status == :ok
    events = plan.events.each_with_index.map { |event, i| {"id" => i + 1, "actor" => players.first, "action" => event.action, "value" => event.value} }
    replay = game.replay(session, events, repo)
    raise "Binary replay rejected" unless replay.accepted_events.length == events.length
    (players + ["Gość"]).each do |viewer|
      view = game.game_view_spec(replay, viewer)
      screen = GameRoomLayout::Screen.new(view_spec: view, history_items: [], user_items: [], users_header: "Gracze")
      screen.form.fields.each do |field|
        strings = []
        strings << field.header if field.respond_to?(:header)
        strings << field.label if field.respond_to?(:label)
        strings.concat(field.options) if field.respond_to?(:options)
        strings.each { |s| raise "Binary field label #{variant}" unless (s.to_s + " — список").valid_encoding? }
      end
      windows += 1
    end
    message = game.table_options_announcement(options)
    raise "Binary options summary" unless (message + " — słowo").valid_encoding?
  end
end
repository = GameRoomKrowa::WordRepository.default
raise "Noun entries lost or duplicated" unless repository.words.length == 85_135 && repository.words.uniq.length == 85_135
raise "Polish nouns corrupted" unless repository.include?("żółć")
%w[łam zacios zaciosy prosię silnia silnie afro szmat ksero
  szamanka szamanki sokownik sokowniki geomanta geomantka geomanci geomantki
  mop mopy bus busy pub puby tarta tarty świrus świrusy świruska świruski
  token tokeny geomancje geomancja
  nekromanta nekromanci nekromantka nekromantki nekromancja nekromancje
  ranking rankingi odsłona odsłony billing billingi kasting kastingi
  halling hallingi hosting hostingi leasing leasingi lifting liftingi
  ścierak ścieraki roaming roamingi szpring szpringi pluszak pluszaki oscypek oscypki].each do |word|
  raise "Added noun missing from binary dictionary: #{word}" unless repository.include?(word)
end
%w[alias aliasy podolog podolodzy podolożka podolożki wibrys wibrysy kodek kodeki polik poliki kebab kebaby].each do |word|
  raise "Requested noun missing from binary dictionary: #{word}" unless repository.include?(word)
end
%w[cytacik cytaciki owocek owocki].each do |word|
  raise "Removed noun remains in binary dictionary: #{word}" if repository.include?(word)
end
provider = GameRoomKrowa::SjpDefinitionProvider.new(fetcher: ->(_uri) { '<p><b>znaczenie:</b></p></div><p>Żółć &amp; słowo.<br>Drugi wiersz.</p>'.b })
raise "Binary SJP decoding" unless provider.definition_for("żółć") == "Żółć & słowo.\nDrugi wiersz."
html = KrowaSjpHtml.entry('pić', {'H' => %w[piły piła]}, 'Czasownik.') +
  KrowaSjpHtml.entry('piła', {'M' => %w[piły pile], 'N' => %w[piłach]}, 'Narzędzie.') +
  KrowaSjpHtml.entry('Piła', {'M' => %w[Piły Pile]}, 'Miasto.')
requests = []
provider = GameRoomKrowa::SjpDefinitionProvider.new(fetcher: ->(uri) { requests << uri.to_s; html.b })
raise "Binary SJP noun selection" unless provider.definition_for('PIŁY'.b) == "piła\nNarzędzie."
raise "Binary SJP URL" unless requests == ['https://sjp.pl/pi%C5%82y']
raise "Binary SJP Unicode suffix rule" unless GameRoomKrowa::SjpNounForms.nominative?(
  'kości', 'kość', {'M' => %w[kości kością], 'N' => %w[kościach]}
)
raise "Binary SJP indeclinable" unless provider.parse(KrowaSjpHtml.entry('menu', {}, 'Spis potraw.').b, word: 'menu') == "menu\nSpis potraw."
details = GameRoomGames::KrowaAttemptListView.new(game, selection: -> { 'żółć' }) do |word|
  {word: word, words: ['żółć']}
end
details.field.trigger(:before_focus)
raise 'Binary attempt list encoding' unless details.field.options == ['żółć. 4'] &&
  (details.field.header + ' — lista').valid_encoding?
$rules_english = false
GameRoomTestLocalization.use_language('pl')
polish_details = GameRoomGames::KrowaAttemptListView.new(game, selection: -> { 'żółć' }) do |word|
  {word: word, words: ['żółć']}
end
polish_details.field.trigger(:before_focus)
raise 'Polish attempt list labels' unless polish_details.field.header == 'Lista prób' &&
  polish_details.field.options == ['żółć. 4']
puts "PASS Krowa binary: #{windows} views PL/EN/fallback, Polish nouns and SJP, merged unique noun database"
