# encoding: UTF-8
# Natywne kontrolki/klawiatura; SpeechOutput i NVDA wyłącznie w pamięci.
require_relative '../support/tournament_native'
require_relative '../support/tournament_public_ui'
require_relative '../../lib/tournaments/public_screen'
require_relative '../../lib/tournaments/operations_screen'
GameRoomLocalization.boot(settings: {'interface_language' => 'en', 'known_languages' => ['en']})

# Zwykły Form nie ma lokalnego interaction/guardu: zachowuje dokładnie jedno
# field.focus bez argumentów, bez dodawania zdarzeń całego Form#focus.
[0, 1, 2].each do |origin|
  [13, 27].each do |close_key|
    driver = TournamentNativeDriver.new
    fields = [ListBox.new(['A', 'B'], header: 'Zwykły formularz', index: 1, quiet: true),
      GameRoomUI::HelpText.new('Opis', type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
        text: 'Niezmienny tekst', quiet: true), Button.new('Koniec')]
    form = GameRoomUI::Form.new(fields, quiet: true)
    form.cancel_button = fields.last
    fields.last.on(:press) { form.resume }
    form.index = origin
    fields[1].index, fields[1].check = 2, 6
    events, counts = [], nil
    armed = false
    target = fields[origin]
    [:before_focus, :focus].each { |event| target.on(event) { events << event if armed } }
    native_focus = target.method(:focus)
    target.define_singleton_method(:focus) do |*arguments|
      events << [:control_focus, arguments] if armed
      native_focus.call(*arguments)
    end
    driver.step('Zwykły formularz') do
      armed = true
      form.game_room_hotkey_action(1).call
      armed = false
      speech = SpeechOutput.calls.drop(counts[0]).map(&:first)
      braille = NVDA.calls.drop(counts[1]).map(&:first)
      assert(speech.length == 1 && braille.length == 1, 'Domyślna pomoc zmieniła liczbę prezentacji')
      assert(events == [[:control_focus, []]], 'Domyślna pomoc zmieniła kontrakt field.focus')
      expected = origin == 0 ? 'Zwykły formularz: B' : origin == 1 ? 'Opis' : 'Koniec'
      assert((speech + braille).all? { |value| value.start_with?(expected) }, 'Domyślny powrót odczytał inne pole')
      assert(form.index == origin && fields.first.index == 1 && form.fields[origin].equal?(target), 'Pomoc podmieniła pole/wiersz')
      assert([fields[1].text, fields[1].index, fields[1].check] == ['Niezmienny tekst', 2, 6], 'Pomoc zmieniła tekst/caret')
      assert(!form.instance_variable_get(:@game_room_help_open), 'Pomoc pozostawiła znacznik otwarcia')
      assert(!EltenAPI::KeyboardState.pressed?(close_key), 'Klawisz zamknięcia wyciekł do rodzica')
    end
    driver.step('Keyboard shortcuts', [close_key]) do |help|
      help.game_room_hotkey_action(1).call
      form.game_room_hotkey_action(1).call
      counts = [SpeechOutput.calls.length, NVDA.calls.length]
    end
    driver.step('Zwykły formularz', [27])
    form.wait
    driver.finish
    assert(driver.forms.length == 2, 'Domyślna pomoc dopuściła rekurencyjny modal')
    puts "PASS domyślna pomoc bez lokalnego guardu: pole=#{origin}, zamknięcie=#{close_key}; field.focus=1, mowa=1, brajl=1"
  end
end

class HelpReturnProbeError < StandardError; end
# Błąd po resume pomocy: ta sama instancja wyjątku musi dotrzeć do wywołującego.
# Cleanup wspólnego helpera oraz lokalne ensure pozostają aktywne bez rescue.
[:default, :public_list, :preview, :operations].each do |kind|
  driver = TournamentNativeDriver.new
  parent, instance, counts = nil, nil, nil
  calls, events = [], []
  armed = false
  error = HelpReturnProbeError.new('Celowy błąd powrotu F1')
  header = {default: 'Zwykły formularz', public_list: 'Tournaments', preview: /\APróba 11 — Łódź — /,
    operations: 'Tournament operations'}.fetch(kind)
  snapshot = TournamentPublicUI.snapshot
  rows = [TournamentPublicUI.record('attempted')].freeze
  driver.step(header) do |form|
    parent = form
    form.index = kind == :preview ? 0 : 1 unless kind == :default
    target = form.fields[form.index]
    [:before_focus, :focus].each { |event| target.on(event) { events << event if armed } }
    native_focus = target.method(:focus)
    target.define_singleton_method(:focus) do |*arguments|
      events << :control_focus if armed
      native_focus.call(*arguments)
    end
    armed = true
    caught = nil
    begin
      form.game_room_hotkey_action(1).call
    rescue HelpReturnProbeError => exception
      caught = exception
    end
    armed = false
    assert(caught.equal?(error), 'F1 połknęło albo zastąpiło błąd programu')
    assert(!form.instance_variable_get(:@game_room_help_open), 'Wyjątek nie posprzątał wspólnej pomocy')
    assert(!instance.instance_variable_get(:@busy), 'Wyjątek pozostawił busy') if instance
    expected = kind == :default ? [] : [:before_focus, :control_focus, :focus]
    assert(events == expected, 'Wyjątek zmienił kontrakt końcowego focuse/ensure')
    number = kind == :default ? 0 : 1
    assert([SpeechOutput.calls.length - counts[0], NVDA.calls.length - counts[1]] == [number, number],
      'Wyjątek dodał niezamierzoną prezentację')
    baseline = [:public_list, :operations].include?(kind) ? [:load] : []
    assert(calls == baseline, 'Wyjątek uruchomił callback rodzica')
    driver.on_resume = nil
    form.game_room_hotkey_action(1).call
    assert(!form.instance_variable_get(:@game_room_help_open), 'Po wyjątku nie można ponownie zamknąć pomocy')
    if kind == :preview
      actions=form.fields.first
      assert(actions.is_a?(ListBox), 'Podgląd nie zaczyna się listą działań')
      actions.index=actions.options.index('Refresh')
      actions.trigger(:select)
    elsif kind != :default
      TournamentPublicUI.button(form, 'Refresh').press
    end
    assert(calls == (kind == :default ? [] : baseline + [:load]), 'Po wyjątku busy nie dopuściło świadomego Refresh')
  end
  driver.step('Keyboard shortcuts', [13]) { counts = [SpeechOutput.calls.length, NVDA.calls.length] }
  driver.step('Keyboard shortcuts', [27])
  driver.step(header, [27])
  driver.on_resume = ->(form) { raise error unless form.equal?(parent) }
  options = {load: -> { calls << :load; snapshot }, join: ->(*) { calls << :join; nil }, alert: ->(*) {}}
  case kind
  when :default
    field = ListBox.new(['A'], header: header, quiet: true)
    back = Button.new('Back')
    form = GameRoomUI::Form.new([field, back], quiet: true)
    form.cancel_button = back
    back.on(:press) { form.resume }
    form.wait
  when :public_list
    args = TournamentPublicUI.arguments(snapshot, **options).reject { |key, _| [:publication, :snapshot].include?(key) }
    instance = GameRoomTournaments::PublicScreen.new(**args)
    instance.run
  when :preview
    instance = GameRoomTournaments::PublicPreview.new(**TournamentPublicUI.arguments(snapshot, **options))
    instance.wait
  when :operations
    instance = GameRoomTournaments::OperationsScreen.new(program: Object.new,
      load: -> { calls << :load; rows }, reconcile: ->(*) { calls << :reconcile; nil }, alert: ->(*) {},
      mode_label: TournamentPublicUI::MODE, actor: TournamentPublicUI::ACTOR)
    instance.run
  end
  driver.finish
  puts "PASS F1 exception #{kind}: propagacja tej samej instancji, cleanup pomocy/busy, następna pomoc i świadomy Refresh"
end
