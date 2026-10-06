require_relative "../support/game_option_editor_native"

def assert(condition, message)
  NativeOptionTest.assert(condition, message)
end

[
  [EditBox, :set_text, "src/ui/controls/edit_box.rb"],
  [EditBox, :update, "src/ui/controls/edit_box.rb"],
  [Form, :wait, "src/ui/form.rb"],
  [Form, :update, "src/ui/form.rb"],
  [Form, :hide, "src/ui/form.rb"],
  [CheckBox, :update, "src/ui/controls/check_box.rb"],
  [CheckBox, :focus, "src/ui/controls/check_box.rb"],
  [ListBox, :update, "src/ui/controls/list_box.rb"],
  [Button, :press, "src/ui/controls/button.rb"]
].each { |type, method, source| NativeOptionTest.native_method(type, method, source) }
assert(!EditBox.method_defined?(:text=), "A fake text= setter hides the native regression")
assert(GameRoomUI::Form.superclass.equal?(Form), "Game Room is not using the native Form")
assert(NativeOptionSource.loaded.key?(File.join(NativeOptionSource::ROOT, "lib/game_option_editor.rb")), "Option editor bypassed binary loading")

scenarios = []
%w[en pl].each do |language|
  NativeOptionTest.language = language
  game = GameRoomGames::MilleBornes.new
  defaults = GameRoomGames::MilleBornes::DEFAULT_DECK_COUNTS
  driver = NativeOptionTest::Driver.new(game, creating_table: true)
  assert(driver.form.index == 0, "Initial form focus changed")
  defaults.each do |type, count|
    key = "#{type}_cards"
    assert(driver.control(key).instance_of?(EditBox), "#{key} is not an actual native EditBox")
    assert(!driver.visible?(key), "Default count #{key} is unexpectedly visible")
    assert(driver.control(key).text == count.to_s, "Initial hidden #{key} was not reset to its actual deck default")
  end
  assert(driver.control("target_score").text == "5000", "Initial target score changed")
  driver.focus(driver.form.accept_button)
  driver.press([13])
  configuration = driver.finished
  assert(configuration == { game_options: game.default_options, private_table: false }, "Native creation changed defaults")
  assert(driver.program.remembers == [[game.id, game.default_options]], "Create did not remember exactly once after submission")
  assert(driver.program.alerts.empty?, "Default creation raised a validation alert")
  scenarios << "#{language}:initial-create"

  driver = NativeOptionTest::Driver.new(game, creating_table: true)
  driver.toggle("custom_deck")
  assert(driver.visible?("25_cards"), "Custom deck did not reveal native integer fields")
  driver.number("25_cards", 17)
  assert(!driver.visible?("counterflow_cards") && !driver.visible?("end_counterflow_cards"), "Counterflow counts visible while disabled")
  assert(!driver.visible?("instant_repair_cards"), "Joker count visible while disabled")
  driver.toggle("counterflow")
  assert(driver.visible?("counterflow_cards") && driver.visible?("end_counterflow_cards"), "Counterflow counts remain hidden")
  driver.number("counterflow_cards", 7)
  driver.toggle("include_instant_repairs")
  assert(driver.visible?("instant_repair_cards"), "Joker count remains hidden")
  driver.number("instant_repair_cards", 4)
  GameRoomGames::MilleBornes::SAFETIES.each do |type|
    assert(driver.visible?("#{type}_cards"), "Enabled safety count hidden")
  end
  driver.toggle("include_safeties")
  GameRoomGames::MilleBornes::SAFETIES.each do |type|
    assert(!driver.visible?("#{type}_cards"), "Disabled safety count visible")
  end
  driver.toggle("include_safeties")
  driver.toggle("custom_deck")
  defaults.each do |type, count|
    key = "#{type}_cards"
    assert(!driver.visible?(key), "Disabling custom deck did not hide #{key}")
    assert(driver.control(key).text == count.to_s, "Disabling custom deck did not reset #{key}")
  end
  driver.toggle("custom_deck")
  assert(driver.control("25_cards").text == defaults.fetch("25").to_s, "Re-enabling restored stale custom count")
  assert(driver.visible?("counterflow_cards") && driver.visible?("instant_repair_cards"), "Re-enabling lost optional count visibility")
  driver.number("25_cards", 19)
  driver.focus("target_score")
  driver.press([13])
  configuration = driver.finished
  assert(configuration.fetch(:game_options).fetch("25_cards") == 19, "Create lost native numeric input")
  assert(game.deck_counts_for(configuration.fetch(:game_options)).fetch("25") == 19, "Submitted count did not affect the actual deck")
  assert(driver.program.remembers.length == 1 && driver.program.alerts.empty?, "Custom create did not submit exactly once")
  scenarios << "#{language}:custom-reset-create"

  [:escape, :button].each do |cancellation|
    driver = NativeOptionTest::Driver.new(game, creating_table: true)
    driver.toggle("custom_deck")
    driver.number("25_cards", 23)
    driver.focus(driver.form.cancel_button) if cancellation == :button
    driver.press(cancellation == :button ? [32] : [27])
    assert(driver.finished.nil?, "Native #{cancellation} cancellation returned options")
    driver.pristine
    scenarios << "#{language}:cancel-#{cancellation}"
  end

  initial = game.normalize_options("custom_deck" => true, "25_cards" => 18)
  driver = NativeOptionTest::Driver.new(game, initial_options: initial, submit_label: "Save changes")
  assert(driver.control("25_cards").text == "18", "Edit mode lost initial custom counts")
  assert(driver.form.fields.grep(CheckBox).length == game.effective_option_definitions.count { |entry| entry.kind.to_s == "boolean" }, "Edit mode unexpectedly added table privacy")
  driver.number("25_cards", 21)
  driver.focus(driver.form.accept_button)
  driver.press([32])
  options = driver.finished
  assert(options == initial.merge("25_cards" => 21), "Edit mode changed unrelated options or result shape")
  driver.pristine
  scenarios << "#{language}:edit"

  rummy = GameRoomGames::Rummy.new
  driver = NativeOptionTest::Driver.new(rummy)
  assert(driver.control("score_limit").text == "1000", "Rummy score default changed")
  driver.toggle("elimination")
  assert(driver.control("score_limit").text == "500", "Rummy elimination did not update the native score field")
  driver.toggle("elimination")
  assert(driver.control("score_limit").text == "1000", "Rummy normal mode did not restore the default score")
  driver.number("score_limit", 735)
  driver.toggle("elimination")
  assert(driver.control("score_limit").text == "735", "Rummy variant overwrote an explicit custom score")
  driver.toggle("elimination")
  assert(driver.control("score_limit").text == "735", "Rummy reverse variant overwrote an explicit custom score")
  driver.focus(driver.form.accept_button)
  driver.press([13])
  assert(driver.finished.fetch("score_limit") == 735, "Rummy submission lost custom score")
  scenarios << "#{language}:rummy"
end

assert(!NativeOptionUI.spoken.empty?, "Native controls never produced focus/state speech")
assert(NativeOptionUI.spoken.any? { |text| text.include?("Pole wyboru") }, "Polish host checkbox role was not exercised")
puts JSON.generate(status: "passed", checks: NativeOptionTest.checks, scenarios: scenarios,
  source: NativeOptionSource.package_path || "binary checkout sources", host: EltenTestHost.root,
  native_setter: EditBox.instance_method(:set_text).source_location,
  scope: "Actual configure_game_options/editor/models and catalogs; native Form/EditBox/CheckBox/ListBox/Button; simulated OS keyboard, speech and storage; no installation or network")
