require_relative "../support/private_table_creation_encoding"

# Exercise the new category through binary-loaded app sources and the real
# host checkbox focus method, including untranslated labels beside Russian UI.
native_checkbox = EltenAPI::Controls.const_get(:CheckBox)
app = EltenGameRoom.allocate
lobby = LobbyRepository.allocate
app.instance_variable_set(:@lobby, lobby)
app.define_singleton_method(:widget_table_available?) { |_snapshot| true }
sources = ["Read table messages outside the table window", "Play a sound for my turn outside the table window"]
polish = ["Odczytuj komunikaty stołu poza jego oknem", "Sygnalizuj dźwiękiem moją turę poza oknem stołu"]
checks = 0

using GameRoomLocalization::Translations

%w[pl en ru fallback].each do |language|
  $option_host_language = language == 'fallback' ? 'ru' : language
  GameRoomTestLocalization.use_language(language)
  expected = sources.map { |text| _(text) }
  Form.option_encoding_driver = lambda do |form|
    raise "Wrong initial settings category" unless form.fields.first.index.to_i == 0 &&
      form.fields.first.options.first == _("General")
    visible = form.fields - form.hidden_controls
    controls = visible.select { |field| field.is_a?(CheckBox) }.first(2)
    raise "Background controls not in General" unless controls.map(&:label) == expected
    controls.each do |control|
      raise "Background option default disabled" unless control.checked
      [false, true].each do |state|
        native_checkbox.new(control.label, checked: state).focus
        speech = $spoken_messages.last
        raise "Native background checkbox lost UTF-8" unless speech.encoding == Encoding::UTF_8 &&
          speech.valid_encoding? && speech.start_with?(control.label)
        checks += 1
      end
      control.checked = false
    end
    form.accept_button.trigger(:press)
  end
  saved = GameRoomScreens::Settings.new({}, games: []).wait
  raise "Background choices not saved independently" unless saved["background_table_speech"] == false &&
    saved["background_turn_sound"] == false

  Form.option_encoding_driver = lambda do |form|
    sections = form.fields.first
    sections.index = 2
    sections.trigger(:move)
    controls = form.fields - form.hidden_controls
    note = controls.find { |field| field.is_a?(EditBox) }
    raise 'Restricted server preferences hide the local notification policy' unless controls[1].is_a?(ListBox)
    raise 'Restricted subscriptions have no read-only explanation' unless note &&
      note.flags & EditBox::Flags::ReadOnly != 0
    raise 'Restricted explanation is not UTF-8' unless [note.text, note.header].all? do |text|
      text.encoding == Encoding::UTF_8 && (text + ' Флажок').valid_encoding?
    end
    expected_note = _("New-table subscriptions are unavailable without access to server settings. Other settings can still be changed.")
    raise 'Restricted explanation has the wrong language' unless note.text.start_with?(expected_note)
    form.accept_button.trigger(:press)
  end
  restricted = GameRoomScreens::Settings.new({}, games: [], table_watch_available: false).wait
  raise 'Unknown subscription selection leaked into saved preferences' if restricted.key?('table_watch_games')

  %w[waiting playing].each do |status|
    row = { "owner" => "Żaneta".b, "game" => "uno", "status" => status, "max_players" => 8 }
    bot = GameRoomParticipants.bot_id(12, 1, name_token: "pl01")
    snapshot = LobbyRepository::TableSnapshot.new(table: row, members: ["Żaneta".b, "Observer"],
      bots: [bot], observers: ["Observer"])
    state_label = status == "waiting" ? _("open") : _("game in progress")
    expected_table = "Żaneta, 2/8, #{state_label}"
    table = app.send(:table_join_label, snapshot)
    widget = app.send(:widget_table_label, snapshot)
    raise "Table label lost count/status/Unicode: #{table.inspect}" unless table == expected_table &&
      table.encoding == Encoding::UTF_8 && table.valid_encoding?
    expected_widget = _("%{game}, %{table}") % {game: app.send(:game_name, 'uno'), table: expected_table}
    raise "Widget label differs from the table list" unless widget == expected_widget && widget.valid_encoding?
  end
end

puts "PASS binary General settings: #{checks} native checkbox states; PL/EN/fallback table status, bot and observer counts"
