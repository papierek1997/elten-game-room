require_relative "../../support/binary_rule_dictionary"

def assert(condition, message); raise message unless condition; end

%w[pl en fallback].each do |language|
  $rules_english = language != "pl"
  GameRoomTestLocalization.use_language(language)
  game = GameRoomGames::Tysiac.new
  players = ["Żaneta", "Łukasz"]
  options = game.normalize_options("variant" => "two_players", "talon_size" => "3")
  session = { "__players" => players, "options" => JSON.generate(options) }
  repository = GameRoomSavedGameArchive::ReplayRepository.new
  events = [
    { "id" => 1, "actor" => players.first, "action" => "deal", "value" => "1|0|000102030405060708090a0b0c0d0e0f" },
    { "id" => 2, "actor" => players.last, "action" => "bid", "value" => "100" },
    { "id" => 3, "actor" => players.first, "action" => "bid", "value" => "pass" }
  ]
  replay = game.replay(session, events, repository)
  emitted = []
  apply = lambda do
    assert(emitted.length == 1, "control did not emit exactly one action")
    status, plan = game.action_for(emitted.shift, replay, players.last)
    assert(status == :ok, "UI action failed: #{status}")
    plan.events.each do |command|
      events << { "id" => events.length + 1, "actor" => players.last, "action" => command.action, "value" => command.value }
    end
    replay = game.replay(session, events, repository)
    assert(replay.accepted_events.length == events.length, "binary replay rejected UI action")
  end
  surface = GameSurfaces.build(game.surface_spec(replay, players.last))
  surface.on_action { |action| emitted << action }
  assert(surface.fields.length == 1, "talon choice has unnecessary fields")
  field = surface.fields.first
  labels = language == "pl" ? ["Pierwszy musik", "Drugi musik"] : ["First talon", "Second talon"]
  assert(field.options == labels, "talon choices not localized")
  assert((field.header + " — список").valid_encoding?, "talon header encoding")
  field.index = 1
  field.trigger(:select, [1])
  apply.call
  assert(events.last["action"] == "take_talon" && events.last["value"] == "1", "wrong talon chosen by Enter")
  assert(replay.state[:phase] == :discarding, "binary phase did not change")
  shortcuts = game.game_shortcuts(replay, players.last)
  contract_key = shortcuts.find { |entry| entry.key == 'r' && entry.modifiers.to_a.empty? }
  surrender_key = shortcuts.find { |entry| entry.key == 'r' && entry.modifiers.to_a == [:shift] }
  assert(contract_key.message == "#{players.last}: 100", 'R did not retain the Unicode bidder and exact contract')
  assert(contract_key.label == (language == 'pl' ? 'odczytaj bieżący kontrakt' : 'read the current contract'), 'R label not localized')
  assert(surrender_key.action_name == 'surrender' && surrender_key.kind == :action, 'Shift+R is not the standard surrender action')
  assert((contract_key.label + ' — контракт').valid_encoding?, 'R label encoding')
  3.times do |index|
    surface = GameSurfaces.build(game.surface_spec(replay, players.last))
    surface.on_action { |action| emitted << action }
    field = surface.fields.first
    assert(field.header.include?((3 - index).to_s), "remaining discard count missing")
    assert((field.header + " — список").valid_encoding?, "discard header encoding")
    assert(field.options.length == 12 - index, "wrong number of hand cards")
    field.trigger(:select, [2])
    apply.call
    assert(events.last["action"] == "discard_card", "Enter played/passed instead of setting aside")
    own = game.describe_event(events.last, repository, replay, players.last).join(" ")
    prefix = language == "pl" ? "Odkładasz:" : "You set aside"
    assert(own.include?(prefix), "own discard not translated")
    assert((own + " — сообщение").valid_encoding?, "discard announcement encoding")
  end
  assert(replay.state[:phase] == :contract, "binary discard never finished")
  surface = GameSurfaces.build(game.surface_spec(replay, players.last))
  surface.on_action { |action| emitted << action }
  surface.fields.first.trigger(:select, [0])
  apply.call
  assert(events.last(2).map { |event| event["action"] } == %w[contract play], "Enter does not accept contract and lead")
  # The shared settings document and Ctrl+R use exactly the visible variant.
  summary = game.table_options_announcement(options)
  assert(summary.include?(language == "pl" ? "Dwie osoby" : "Two players"), "Ctrl+R omits variant")
  assert((summary + " — параметры").valid_encoding?, "variant summary encoding")
  book = game.rule_sections.find { |section| section.id == :two_players }
  assert(book && book.paragraphs.all? { |text| text.encoding == Encoding::UTF_8 && text.valid_encoding? }, "new rule section encoding")
  assert(book.title == (language == "pl" ? "Dwie osoby: wybór jednego z dwóch musików" : "Two players: choose one of two talons"), "new rules use wrong language")

  state = game.send(:initial_state, players, options)
  state.merge!(round: 1, taker: players.last, contract: 100)
  state[:scores][players.first] = 870
  state[:round_points][players.first] = 30
  history = []
  game.send(:complete_round, state, 20, history, surrendered: false)
  arrival = history.find { |entry| entry.kind == :barrel }.text
  assert(arrival == (language == "pl" ? "Żaneta trafia na beczkę." : "Żaneta is now on the barrel."), "barrel announcement not localized")
  scores = game.send(:scores_text, state, sorted: true)
  assert(scores.include?(language == "pl" ? "Żaneta: 880, na beczce" : "Żaneta: 880, on the barrel"), "S barrel marker not localized")
  assert(([arrival, scores].join + " — очки").valid_encoding?, "barrel speech mixes encodings")
end

puts "PASS binary Tysiac UI: real talon/discard/contract controls, native dictionary, PL/EN/fallback, Ctrl+R and barrel speech"
