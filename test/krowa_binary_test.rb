require_relative "support/binary_rule_dictionary"
BinaryRulesLoad.load(File.join(BinaryRulesLoad::ROOT, "games/krowa_support/client.rb"))

class KrowaBinaryStorage
  def initialize; @data = {}; end
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
raise "Noun entries lost or duplicated" unless repository.words.length == 98_178 && repository.words.uniq.length == 84_873
raise "Polish nouns corrupted" unless repository.include?("żółć")
provider = GameRoomKrowa::SjpDefinitionProvider.new(fetcher: ->(_uri) { '<p><b>znaczenie:</b></p></div><p>Żółć &amp; słowo.<br>Drugi wiersz.</p>'.b })
raise "Binary SJP decoding" unless provider.definition_for("żółć") == "Żółć & słowo.\nDrugi wiersz."
puts "PASS Krowa binary: #{windows} views PL/EN/fallback, Polish nouns and SJP, original duplicate-preserving database"
