require_relative 'support/host_source'
require_relative "support/binary_rule_dictionary"

module Session
  def self.name; 'Alice'; end
end

def assert(value, message); raise message unless value; end
native_dictionary = $rules_dictionary
assert(GameRoomGames::Yahtzee::CATEGORY_LABELS.fetch("misery") == "Nędza", "Misery was not translated when binary source loaded")
class CheckBox < FakeControl
  attr_reader :label
  attr_accessor :checked
  def initialize(label, checked: false); super(); @label, @checked = label, checked; end
end unless defined?(CheckBox)
module Configuration
  def self.controlspresentation; :voice_only; end
end
module EltenAPI; module Controls; class FormField; end; end; end
host = EltenTestHost.root
load File.join(host, "src/ui/controls/check_box.rb")
native_checkbox = EltenAPI::Controls.const_get(:CheckBox)
def p_(_context, text); "Флажок #{text}"; end
class Form
  def resume; end
end
old_wait = Form.instance_method(:wait)
driver = nil
Form.send(:define_method, :wait) { driver.call(self) }
begin
  %i[pl en fallback].each do |language|
    $rules_english = language == :en
    GameRoomTestLocalization.use_language(language)
    $rules_dictionary = language == :fallback ? BinaryRuleDictionary.new({}) : native_dictionary
    expected = ->(en, pl) { language == :pl ? pl : en }
    game_ids = EltenGameRoom::GAME_REGISTRY.ids
    added_games = game_ids - GameRoomPreferences::LEGACY_LOBBY_GAME_IDS
    settings = GameRoomPreferences.normalize({"lobby_games" => ["uno"], "table_watch_games" => []}, game_ids)
    expected_lobby = game_ids.select { |id| id == "uno" || added_games.include?(id) }
    assert(settings["lobby_games"] == expected_lobby, "binary lobby migration missed existing new games")
    games = game_ids.map { |id| {id: id, name: id} }
    writes = []
    driver = lambda do |form|
      form.fields.each do |field|
        labels = []
        labels << field.header if field.respond_to?(:header)
        labels << field.label if field.respond_to?(:label)
        labels += field.options if field.respond_to?(:options)
        labels.compact.each { |label| assert((label + " — список").valid_encoding?, "mixed control encodings") }
        native_checkbox.new(field.label, checked: field.checked).focus if field.is_a?(CheckBox)
      end
      if form.fields.first.header == expected.call("Settings", "Ustawienia")
        form.fields.first.index = form.fields.first.options.index(expected.call('Lobby messages', 'Komunikaty lobby')) || raise('Missing lobby category')
        form.fields.first.trigger(:move)
        lobby_list = form.fields.find { |field| field.is_a?(ListBox) && field.header == expected.call('Games covered by lobby messages', 'Gry objęte komunikatami lobby') }
        assert(lobby_list.is_a?(ListBox) && lobby_list.game_indices.map { |index| game_ids[index] } == expected_lobby,
          "binary Settings lost migrated lobby checks")
        assert(settings["table_watch_games"].empty?, "binary migration enabled notification subscriptions")
        form.fields.first.index = form.fields.first.options.index(expected.call('Widget', 'Widget')) || raise('Missing Widget category')
        form.fields.first.trigger(:move)
        list = form.fields.find { |field| field.is_a?(ListBox) && field.header == expected.call("Table shortcuts", "Skróty tworzenia stołów") }
        assert(list && !form.hidden_controls.include?(list), "missing translated inline shortcuts")
        assert(list.options.first == expected.call("Ctrl+1: Not assigned. Press Enter to assign.", "Ctrl+1: Nie przypisano. Wciśnij Enter, aby przypisać."), "preset label language")
        form.index = form.fields.index(list)
        form.accept_button.trigger(:press)
        assert(writes.length == 1 && list.options.first == expected.call("Ctrl+1: Żółty stół. Press Enter to edit.", "Ctrl+1: Żółty stół. Wciśnij Enter, aby edytować."), "immediate assignment/hint missing")
        assert((list.options.first + " — список").valid_encoding?, "assigned hint has binary encoding")
        form.cancel_button.trigger(:press)
      else
        raise "unwanted preset-list or naming window"
      end
    end
    result = GameRoomScreens::Settings.new(settings, games: games,
      preset_editor: ->(_) { {"game" => "makao", "name" => "Żółty stół"} },
      preset_writer: ->(slot, entry) { writes << [slot, entry] }).wait
    assert(result.nil? && writes.length == 1, "parent Cancel undid the local assignment")
    y = GameRoomGames::Yahtzee.new
    assert(y.option_definitions.find { |d| d.key == "upper_bonus" }.label == expected.call("35-point bonus for Ones through Sixes", "Premia 35 punktów za Jedynki–Szóstki"), "bonus label language")
    assert(y.send(:dice_text, dice: [1, 2, 3, 4, 5]) == "1, 2, 3, 4, 5.", "dice prefix returned")
    # Mixed-language names exercise the new dynamic strings, not only rules.
    ludo = GameRoomGames::Ludo.new
    state = ludo.send(:initial_state, ["Łucja", "Żaneta"], ludo.default_options)
    state.merge!(last_roll: 6, last_roll_player: "Żaneta")
    replay = GameRoomGames::Replay.new(players: state[:players], current_player: "Łucja", state: state)
    assert(ludo.shortcut_feature_data(:last_roll, replay, "Łucja")[:message] == "Żaneta, 6.", "binary last roller")
    keys = ludo.custom_game_shortcuts(replay, "Żaneta")
    assert(keys.find { |key| key.key == "1" }.message.start_with?("Żaneta:"), "binary player digit")
    label = keys.find { |key| key.key == "v" && key.modifiers == [:shift] }.choices.first.label
    assert(label == expected.call("Łucja, base", "Łucja, baza"), "binary position label: #{label}")
    makao = GameRoomGames::Makao.new
    option = makao.option_definitions.find { |definition| definition.key == "allow_playable_draw" }
    assert(option.label == expected.call("Allow drawing with a playable card", "Pozwalaj dobierać mimo posiadania pasującej karty"), "drawing option language")
    native_checkbox.new(option.label, checked: true).focus
    # Actual preset -> common creation path, with only network/host I/O replaced.
    notices = []
    original_notice = EltenGameRoom.method(:announce_new_public_table)
    EltenGameRoom.define_singleton_method(:announce_new_public_table) { |row| notices << row }
    begin
      [false, true].each do |privacy|
        preset = GameRoomTablePresets.build(makao,
          {game_options: makao.normalize_options("profile" => "custom", "allow_playable_draw" => false), private_table: privacy}, name: "Żółty stół")
        app = EltenGameRoom.allocate
        app.define_singleton_method(:game_room_settings) { |**_| {"table_presets" => [preset]} }
        app.define_singleton_method(:prepare_widget_program) {}
        app.define_singleton_method(:run_network_task) { |_, **_, &block| block.call }
        app.define_singleton_method(:default_table_name) { "Żółty stół" }
        app.define_singleton_method(:activate_table_transport) { |_| }
        app.define_singleton_method(:play_game_sound) { |_| }
        opened = []
        app.define_singleton_method(:show_table_screen) { |row| opened << row }
        created = []
        lobby = Object.new
        lobby.define_singleton_method(:create_table) do |**values|
          created << values
          result = Struct.new(:table).new({"__id" => "test-table"})
          result.define_singleton_method(:created?) { true }
          result
        end
        app.instance_variable_set(:@lobby, lobby)
        before = notices.length
        app.send(:create_table_from_widget, 0)
        assert(created.length == 1 && opened.length == 1, "binary preset creation path failed")
        assert(created.first[:private_table] == privacy && JSON.parse(created.first[:game_options]) == preset["options"], "binary preset changed options/privacy")
        assert(notices.length - before == (privacy ? 0 : 1), "binary private table was announced")
      end
    ensure
      EltenGameRoom.define_singleton_method(:announce_new_public_table, original_notice)
    end
    %w[yahtzee makao krowa ludo mexican_train axel_pong].each do |id|
      game = EltenGameRoom::GAME_REGISTRY.build(id)
      authored = JSON.parse(File.read(File.join(BinaryRulesLoad::ROOT, "docs/rulebooks/#{id}.json"), encoding: "UTF-8"))
      text = game.rule_book.documents.take(2).map(&:text).join("\n")
      authored["sections"].each do |section|
        section["paragraphs"].each do |pair|
          assert(text.include?(pair.fetch(language == :pl ? "pl" : "en")), "mixed #{id} rules: #{language}")
        end
      end
    end
    # The introduction/attribution belongs to build 231, not every later
    # maintenance release. Keep checking the original entry and the rules.
    introduction = GameRoomChangelog::ENTRIES.find { |entry| entry.build == 231 }
    assert(introduction != nil, "Pong introduction changelog missing")
    credit = introduction.changes.first
    assert(credit.include?("Dragon-Pong") && credit.include?("Axel and balteam"), "Pong attribution is not first")
    assert(GameRoomGames::AxelPong.new.rule_book.documents.first.text.include?(GameRoomRules.translate(credit)), "Pong rules and changelog attribution differ")
    # Krowa's command carries a round identity through the normal surface.
    game = GameRoomGames::Krowa.new
    repo = GameRoomSavedGameArchive::ReplayRepository.new
    session = {"__id" => 1, "__players" => ["Łucja"], "options" => JSON.generate(game.default_options.merge("variant" => "random"))}
    replay = game.replay(session, [], repo)
    replay.state.merge!(phase: :active, round: 3, length: 13)
    command = game.surface_spec(replay, "Łucja").parts.flat_map { |p| p.surface.respond_to?(:commands) ? p.surface.commands : [] }.find { |c| c.id == "reroll" }
    assert(command.label == expected.call("Draw another word", "Przelosuj słowo") && command.payload == {"round" => 3}, "reroll label/round identity")
  end
ensure
  Form.send(:define_method, :wait, old_wait)
  $rules_dictionary, $rules_english = native_dictionary, false
  GameRoomTestLocalization.use_language(:pl)
end
puts "Binary feedback UI: PL/EN/fallback, native checkbox, lobby defaults, presets, Nędza/bonus, six rulebooks, Pong credits and Krowa command OK"
