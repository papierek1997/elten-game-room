if ARGV.delete("--binary-options")
  require_relative "../../support/game_option_encoding"
  program = EltenGameRoom.allocate
  program.define_singleton_method(:read_json) { |_path, default:| default }
  program.define_singleton_method(:alert) { |message| raise message }
  checks = { forms: 0, checkbox_states: 0, labels: 0 }
  Form.option_encoding_driver = GameOptionEncodingFixture.driver(checks)
  %w[en pl ru].each do |language|
    $option_host_language = language
    GameRoomTestLocalization.use_language(language)
    game = GameRoomGames::MilleBornes.new
    [false, true].repeated_permutation(4).each do |custom, safeties, counterflow, instant|
      values = { "custom_deck" => custom, "include_safeties" => safeties,
        "counterflow" => counterflow, "include_instant_repairs" => instant }
      if custom
        values.merge!("25_cards" => 100, "right_of_way_cards" => 3, "instant_repair_cards" => 0,
          "counterflow_cards" => 0, "end_counterflow_cards" => 100)
      end
      expected = game.normalize_options(values)
      actual = program.send(:configure_game_options, game, initial_options: expected)
      raise "Binary form changed options: #{values.inspect}" unless actual == expected
      raise "Binary form changed the deck" unless game.deck_counts_for(actual) == game.deck_counts_for(expected)
    end
  end
  puts "PASS binary custom deck option forms: #{checks.inspect}"
  exit
end

require_relative "../../support/elten_array_shuffle"
require_relative "../../support/mille_bornes"
include MilleBornesTest

def custom_options(game, counts = {})
  game.class::CARD_ORDER.to_h { |type| ["#{type}_cards", counts.fetch(type, 0)] }
    .merge("custom_deck" => true)
end

test("default options use one-second bot delay and the ordered standard deck remains unchanged") do
  game = Fixture.new.game
  expected = JSON.parse(File.read(File.join(__dir__, "../../fixtures/contracts/v1/mille_bornes.json"))).fetch("options")
  expected["bot_delay"] = 1
  equal(JSON.generate(expected), JSON.generate(game.default_options), "option shape and order with approved bot delay")
  counts = game.deck_counts_for(game.default_options)
  equal(game.class::CARD_ORDER, counts.keys, "all physical card types in stable order")
  equal(game.class::DECK_COUNTS, counts.reject { |_type, count| count.zero? }, "unchanged baseline counts")
  equal(106, counts.values.sum, "unchanged default deck")
  equal(0, counts.fetch("instant_repair"), "instant repairs disabled by default")
  equal("instant_repair", game.class::CARD_ORDER.last, "new card appended without reordering historical cards")
  counts["25"] = 0
  equal(10, game.deck_counts_for({}).fetch("25"), "callers cannot mutate later decks")
end

test("normal optional families are independent and use authorized fallback counts") do
  game = Fixture.new.game
  [false, true].repeated_permutation(3).each do |safeties, counterflow, instant|
    options = { "include_safeties" => safeties, "counterflow" => counterflow, "include_instant_repairs" => instant }
    counts = game.deck_counts_for(options)
    equal(safeties ? 4 : 0, game.class::SAFETIES.sum { |type| counts.fetch(type) }, "independent safety flag")
    equal(counterflow ? 4 : 0, counts.fetch("counterflow"), "counterflow follows speed-limit default")
    equal(counterflow ? 6 : 0, counts.fetch("end_counterflow"), "end counterflow follows end-limit default")
    equal(instant ? 2 : 0, counts.fetch("instant_repair"), "exactly two optional instant repairs")
    equal(nil, game.options_error(options, player_count: 8), "normal deck remains valid")
    normalized = game.normalize_options(options)
    equal(normalized, game.options_from_json(JSON.generate(normalized)), "normal option round trip")
  end
end

test("legacy counted counterflow survives replay while new normal options reset hidden counts") do
  game = Fixture.new.game
  [[4, 4], [3, 4], [1, 20], [20, 1]].each do |attacks, remedies|
    legacy = { "counterflow" => true, "counterflow_cards" => attacks, "end_counterflow_cards" => remedies }
    normalized = game.normalize_options(legacy)
    equal(attacks, game.deck_counts_for(normalized).fetch("counterflow"), "legacy attack count")
    equal(remedies, game.deck_counts_for(normalized).fetch("end_counterflow"), "legacy remedy count")
    equal(normalized, game.options_from_json(JSON.generate(normalized)), "historical options retained")
    [legacy.merge("custom_deck" => false), game.new_game_options("counterflow" => true)].each do |fresh|
      equal(4, game.deck_counts_for(fresh).fetch("counterflow"), "new normal attack count")
      equal(6, game.deck_counts_for(fresh).fetch("end_counterflow"), "new normal remedy count")
    end
    equal(normalized, game.new_game_options(legacy), "starting an existing legacy table does not silently change its deck")
  end
  custom = game.normalize_options("custom_deck" => true, "counterflow" => true,
    "include_instant_repairs" => true, "25_cards" => 99, "counterflow_cards" => 77, "instant_repair_cards" => 88)
  normal = game.normalize_options(custom.merge("custom_deck" => false))
  equal(game.deck_counts_for("counterflow" => true, "include_instant_repairs" => true), game.deck_counts_for(normal), "custom off restores every canonical count")
  assert(!normal.key?("custom_deck") && !normal.key?("25_cards"), "normal options do not carry hidden custom counts")
  equal(normal, game.normalize_options(normal), "reset options are idempotent")
  equal(custom, game.new_game_options(custom), "custom presets retain their configured deck")
end

test("custom counts cover every type and remain independent from optional family flags") do
  game = Fixture.new.game
  counts = game.class::CARD_ORDER.each_with_index.to_h { |type, index| [type, index + 1] }
  options = custom_options(game, counts).merge("counterflow" => true, "include_instant_repairs" => true)
  equal(counts, game.deck_counts_for(options), "every type configurable in stable order")
  normalized = game.normalize_options(options.transform_keys(&:to_sym).transform_values { |value| value.is_a?(Integer) ? value.to_s : value })
  equal(counts, game.deck_counts_for(normalized), "symbol keys and integer strings")
  equal(normalized, game.options_from_json(JSON.generate(normalized)), "custom option round trip")
  disabled = game.normalize_options(normalized.merge("include_safeties" => false, "counterflow" => false, "include_instant_repairs" => false))
  optional_types = game.class::SAFETIES + %w[counterflow end_counterflow instant_repair]
  optional_types.each do |type|
    equal(0, game.deck_counts_for(disabled).fetch(type), "disabled #{type} excluded from deck")
    equal(counts.fetch(type), disabled.fetch("#{type}_cards"), "disabled #{type} configuration preserved")
  end
  equal(counts, game.deck_counts_for(disabled.merge("include_safeties" => true, "counterflow" => true, "include_instant_repairs" => true)), "reenabling restores configured counts")
end

test("all custom counts enforce inclusive bounds and reject malformed values after normalization") do
  game = Fixture.new.game
  base = { "custom_deck" => true, "counterflow" => true, "include_instant_repairs" => true }
  invalid_values = [nil, false, true, -1, 101, 1.5, "1.5", "", "bad", "NaN", "Infinity", "1e1", "0x10", "1\0", "9" * 256, [], [1], {}, { "count" => 1 }]
  game.class::CARD_ORDER.each do |type|
    [0, 100, "0", "100"].each do |count|
      options = base.merge("#{type}_cards" => count)
      equal(nil, game.options_error(options, player_count: 8), "valid #{type} bound #{count.inspect}")
      equal(count.to_i, game.deck_counts_for(options).fetch(type), "bound retained")
    end
    invalid_values.each do |invalid|
      options = base.merge("#{type}_cards" => invalid)
      error = game.options_error(options)
      assert(error && error.include?("integer from 0 to 100"), "invalid #{type}=#{invalid.inspect} must fail")
      normalized = game.normalize_options(options)
      equal(error, game.options_error(normalized), "malformed count must not become a valid default")
      equal(error, game.options_error(game.options_from_json(JSON.generate(normalized))), "serialized error retained")
      begin
        game.deck_counts_for(normalized)
        raise "invalid custom count produced a deck"
      rescue ArgumentError => failure
        equal(error, failure.message, "deck API rejects invalid counts explicitly")
      end
    end
  end
end

test("custom deck validation checks effective deal capacity and possible scoring") do
  game = Fixture.new.game
  [nil, 2, 3, 8].each do |players|
    size = 6 * (players || 2)
    options = custom_options(game, "25" => size - 1, "go" => 1)
    equal(nil, game.options_error(options, player_count: players), "exact deal capacity accepted for #{players.inspect}")
    short = options.merge("25_cards" => size - 2)
    assert(game.options_error(short, player_count: players).include?(size.to_s), "short deck rejected at actual roster size")
  end
  options = custom_options(game, "stop" => 12)
  assert(game.options_error(options).include?("score points"), "unscorable deck rejected")
  fixture = Fixture.new(players: %w[Alice Bob], options: options)
  status, = game.action_for({ "kind" => "command", "action" => "deal" }, fixture.replay, "Alice", context: fixture.context)
  equal(:invalid, status, "unscorable deck rejected before planning a deal")
  fixture.events << event(1, "Alice", "deal", "1|#{'0' * 32}")
  equal([], fixture.replay.accepted_events, "imported unscorable deal rejected")
  options["extra_tank_cards"] = 1
  equal(nil, game.options_error(options), "one scoring safety suffices")
  assert(game.options_error(options.merge("include_safeties" => false)).include?("score points"), "disabled safeties cannot make a deck scorable")
  options = custom_options(game, "25" => 12)
  assert(game.options_error(options).include?("score points"), "mileage without a possible start rejected")
  %w[go right_of_way instant_repair].each do |type|
    enabled = options.merge("#{type}_cards" => 1, "include_instant_repairs" => true)
    equal(nil, game.options_error(enabled), "#{type} provides a possible start")
  end
  disabled = options.merge("instant_repair_cards" => 100, "include_instant_repairs" => false, "25_cards" => 11)
  assert(game.options_error(disabled).include?("12"), "disabled optional cards cannot fill a short deck")
end

test("deck API does not recurse into options_error and preserves roster normalization") do
  game = Fixture.new.game
  game.define_singleton_method(:options_error) { |*_arguments, **_keywords| raise "deck_counts_for called options_error" }
  equal(106, game.deck_counts_for({}).values.sum, "independent standard deck API")
  equal(106, game.deck_counts_for("custom_deck" => true).values.sum, "independent custom deck API")
  players = Array.new(8) { |index| "Player#{index + 1}" }
  options = game.normalize_options("custom_deck" => true, GameRoomTeams::PLAYERS_KEY => players)
  equal(players, options.fetch(GameRoomTeams::PLAYERS_KEY), "all eight historical roster entries retained")
  assert(!players.equal?(options.fetch(GameRoomTeams::PLAYERS_KEY)), "roster copied")
end

test("custom decks deal complete unique hands at the minimum size and replay deterministically") do
  game = Fixture.new.game
  [2, 3, 8].each do |player_count|
    players = Array.new(player_count) { |index| "Player#{index + 1}" }
    options = custom_options(game, "25" => 6 * player_count - 1, "go" => 1)
    fixture = Fixture.new(players: players, options: options)
    dealt = fixture.start
    hands = dealt.state[:hands].values.flatten
    equal(Array.new(player_count, 6), dealt.state[:hands].values.map(&:length), "six cards per player")
    assert(hands.none?(&:nil?), "no nil cards in a minimum-size deck")
    equal(hands.length, hands.uniq.length, "physical card identifiers unique")
    equal([], dealt.state[:draw_pile], "minimum deck exhausted after dealing")
    equal(dealt.state, fixture.replay.state, "replay preserves the customized deterministic deal")
    short = Fixture.new(players: players, options: options.merge("25_cards" => 6 * player_count - 2))
    status, = short.game.action_for({ "kind" => "command", "action" => "deal" }, short.replay, players.first, context: short.context)
    equal(:invalid, status, "short deck rejected before planning a deal")
    short.events << event(1, players.first, "deal", "1|#{'0' * 32}")
    equal([], short.replay.accepted_events, "imported short-deck deal rejected")
  end
end

test("maximum custom deck includes every physical type without changing the seeded shuffle contract") do
  game = Fixture.new.game
  counts = game.class::CARD_ORDER.to_h { |type| [type, 100] }
  options = custom_options(game, counts).merge("counterflow" => true, "include_instant_repairs" => true)
  fixture = Fixture.new(options: options)
  deck = fixture.game.send(:deck_for, options)
  equal(2200, deck.length, "bounded total deck size")
  equal(deck.length, deck.uniq.length, "all card identifiers unique")
  equal(counts, deck.map { |card| card.split(":").first }.tally, "counts used by the model")
  dealt = fixture.start
  shuffled = GameRoomRandom.shuffle(deck, random: Random.new(dealt.state[:seed].to_i(16)))
  equal(shuffled.drop(fixture.players.length * 6), dealt.state[:draw_pile], "one seeded shuffle with every configured card")
  equal(dealt.state, fixture.replay.state, "maximum-size deck replays")
end

test("read-only table options reveal the actual optional counts without making normal counts editable") do
  game = Fixture.new.game
  [3, 4].each do |attacks|
    options = { "counterflow" => true, "counterflow_cards" => attacks, "end_counterflow_cards" => 4 }
    text = game.table_options_announcement(options)
    definition = game.option_definitions.find { |item| item.key == "counterflow_cards" }
    assert(text.include?("#{definition.label}: #{attacks}"), "historical counterflow count announced")
    assert(!game.option_visible?(definition, options), "normal count is read-only")
  end
  options = { "include_instant_repairs" => true }
  definition = game.option_definitions.find { |item| item.key == "instant_repair_cards" }
  assert(game.table_options_announcement(options).include?("#{definition.label}: 2"), "normal instant repair count announced")
  custom = { "custom_deck" => true, "counterflow" => true, "include_instant_repairs" => true }
  keys = game.notification_option_keys(custom)
  game.class::CARD_ORDER.each { |type| assert(keys.include?("#{type}_cards"), "#{type} option available to notification contract") }
  equal(keys.uniq, keys, "notification keys have no duplicates")
end

require_relative "../../support/game_option_form"

test("option form keeps independent flags visible and resets hidden counts when leaving custom mode") do
  game = GameRoomGames::MilleBornes.new
  program = EltenGameRoom.allocate
  program.define_singleton_method(:read_json) { |_path, default:| default }
  program.define_singleton_method(:alert) { |message| raise message }
  definitions = game.effective_option_definitions
  Form.driver = lambda do |form|
    controls = definitions.to_h do |definition|
      [definition.key, form.fields.find { |field| field.respond_to?(:header) && field.header == definition.label }]
    end
    %w[custom_deck include_safeties counterflow include_instant_repairs].each do |key|
      assert(controls.fetch(key).is_a?(CheckBox), "#{key} is a checkbox")
      assert(!form.hidden_controls.include?(controls.fetch(key)), "#{key} remains visible in normal mode")
    end
    game.class::CARD_ORDER.each do |type|
      control = controls.fetch("#{type}_cards")
      assert(form.hidden_controls.include?(control), "normal #{type} count hidden")
      equal(game.class::DEFAULT_DECK_COUNTS.fetch(type).to_s, control.text, "hidden #{type} count initialized canonically")
    end
    controls.fetch("custom_deck").checked = true
    controls.fetch("custom_deck").trigger(:change)
    assert(!form.hidden_controls.include?(controls.fetch("25_cards")), "ordinary count shown in custom mode")
    assert(!form.hidden_controls.include?(controls.fetch("right_of_way_cards")), "default safety count shown despite omitted true option")
    %w[counterflow_cards end_counterflow_cards instant_repair_cards].each do |key|
      assert(form.hidden_controls.include?(controls.fetch(key)), "disabled optional family #{key} hidden")
    end
    %w[counterflow include_instant_repairs].each do |key|
      controls.fetch(key).checked = true
      controls.fetch(key).trigger(:change)
    end
    game.class::CARD_ORDER.each do |type|
      assert(!form.hidden_controls.include?(controls.fetch("#{type}_cards")), "enabled custom #{type} count shown")
      controls.fetch("#{type}_cards").set_text("77")
    end
    controls.fetch("include_safeties").checked = false
    controls.fetch("include_safeties").trigger(:change)
    game.class::SAFETIES.each do |type|
      assert(form.hidden_controls.include?(controls.fetch("#{type}_cards")), "safety count hidden when disabled")
      equal("77", controls.fetch("#{type}_cards").text, "hidden custom value retained")
    end
    controls.fetch("custom_deck").checked = false
    form.index = form.fields.index(controls.fetch("custom_deck"))
    controls.fetch("custom_deck").trigger(:change)
    equal(controls.fetch("custom_deck"), form.fields[form.index], "changing visibility retains checkbox focus")
    game.class::CARD_ORDER.each do |type|
      equal(game.class::DEFAULT_DECK_COUNTS.fetch(type).to_s, controls.fetch("#{type}_cards").text, "custom off resets #{type}")
    end
    form.fields.find { |field| field.is_a?(Button) && field.label == "Create table" }.trigger(:press)
  end
  options = program.send(:configure_game_options, game)
  equal(game.normalize_options("counterflow" => true, "include_safeties" => false, "include_instant_repairs" => true), options, "normal form persists only canonical effective options")
ensure
  Form.driver = nil
end

test("custom option presets serialize and reopen without changing counts or enabled families") do
  game = GameRoomGames::MilleBornes.new
  program = EltenGameRoom.allocate
  program.define_singleton_method(:read_json) { |_path, default:| default }
  program.define_singleton_method(:alert) { |message| raise message }
  options = game.normalize_options("custom_deck" => true, "counterflow" => true, "counterflow_cards" => 0,
    "end_counterflow_cards" => 0, "include_safeties" => false, "right_of_way_cards" => 0,
    "include_instant_repairs" => true, "instant_repair_cards" => 4, "25_cards" => 100)
  Form.driver = lambda do |form|
    form.fields.find { |field| field.is_a?(Button) && field.label == "Create table" }.trigger(:press)
  end
  actual = program.send(:configure_game_options, game, initial_options: options)
  equal(options, actual, "custom values and disabled-family counts survive reopening")
  preset = GameRoomTablePresets.build(game, { game_options: actual, private_table: false }, name: "Custom deck test")
  stored = JSON.parse(JSON.generate(preset))
  assert(GameRoomTablePresets.valid?(stored, game), "stored custom preset remains valid")
  equal(options, stored.fetch("options"), "preset uses the same normalized options")
  equal(game.deck_counts_for(options), game.deck_counts_for(stored.fetch("options")), "persisted preset preserves effective deck")
  legacy = game.normalize_options("counterflow" => true, "counterflow_cards" => 3, "end_counterflow_cards" => 4)
  legacy_preset = { "game" => game.id, "options" => legacy, "private_table" => false }
  assert(GameRoomTablePresets.valid?(legacy_preset, game), "legacy preset still validates")
  equal(legacy, GameRoomTablePresets.build(game, { game_options: legacy, private_table: false }).fetch("options"), "reusing legacy preset preserves the explicit old deck")
ensure
  Form.driver = nil
end
