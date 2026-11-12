# encoding: UTF-8
require_relative '../support/tournament_native'
require_relative '../support/tournament_public_ui'

source = File.expand_path('../../lib/tournaments/operations_screen.rb', __dir__)
assert(File.file?(source), 'Brak ekranu jawnego sprawdzania operacji turniejowych')
require source
GameRoomLocalization.boot(settings: {'interface_language' => 'en', 'known_languages' => ['en']})

module TournamentOperationsScreenTest
  extend GameRoomTest::Assertions
  HEADER = 'Tournament operations'.freeze
  module_function

  def records
    first = TournamentPublicUI.record('attempted')
    second = JSON.parse(JSON.generate(first))
    second['id'] = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    second['values']['tournament_id'] = 12
    GameRoomTournaments::Publication::Data.freeze_tree([first, second])
  end

  def button(form, label)
    TournamentPublicUI.button(form, label)
  end

  def screen(**options)
    GameRoomTournaments::OperationsScreen.new(program: Object.new,
      load: -> { records }, reconcile: ->(*) { raise 'Podgląd nie może sprawdzać ani wysyłać operacji' },
      alert: ->(*) {}, mode_label: TournamentPublicUI::MODE, actor: TournamentPublicUI::ACTOR, **options)
  end

  def restored_selection
    rows = records
    observations = []
    [:reconcile, :refresh].each do |path|
      driver = TournamentNativeDriver.new
      active = nil
      reads, calls = 0, []
      confirmed = JSON.parse(JSON.generate(rows.last))
      confirmed['status'] = 'confirmed'
      load = -> do
        reads += 1
        next rows if reads == 1
        if path == :reconcile
          assert(active.fields.first.options.any? { |value| value.end_with?('; confirmed') },
            'Wynik musi trafić do widoku przed nieudanym odczytem')
          next nil
        end
        active.fields.first.index = 0
        active.fields.first.trigger(:move)
        active.index = 4
        rows.reverse
      end
      reconcile = ->(id) do
        calls << id
        active.fields.first.index = 0
        active.fields.first.trigger(:move)
        active.index = 4
        confirmed
      end
      driver.press(HEADER, 40)
      driver.press(HEADER, 13)
      driver.step(HEADER) do |form|
        active = form
        details = form.fields[1]
        details.index, details.check = 7, 15
        original_text = details.text.dup
        button(form, path == :reconcile ? 'Check selected operation' : 'Refresh').press
        current = path == :refresh ? rows.reverse : rows
        observations << {path: path, field: form.index,
          id: current[form.fields.first.index]['id'], details: details.text,
          caret: [details.index, details.check], original_text: original_text,
          speech: SpeechOutput.calls.last.first, braille: NVDA.calls.last.first}
      end
      driver.step(HEADER, [27])
      screen(load: load, reconcile: reconcile).run
      driver.finish
      assert_equal(2, reads)
      assert_equal(path == :reconcile ? [rows.last['id']] : [], calls)
    end
    observations.each do |entry|
      assert_equal(1, entry[:field])
      assert_equal(rows.last['id'], entry[:id])
      [:details, :speech, :braille].each do |output|
        assert(entry[output].include?(rows.last['id']) && !entry[output].include?(rows.first['id']),
          "OPS-1 #{entry[:path]}: #{output} opisuje inne ID niż przywrócona lista")
      end
      if entry[:path] == :reconcile
        assert(entry[:details].include?('Registration for tournament 12; confirmed'), 'Szczegóły ukryły potwierdzenie')
      else
        assert_equal(entry[:original_text], entry[:details])
        assert_equal([7, 15], entry[:caret])
      end
    end
    puts 'PASS OPS-1: reconcile/nil i refresh/reorder przywracają pole, ID, szczegóły, mowę/brajl i niezmieniony caret'
  end

  def guarded_help
    [0, 1].each do |origin|
      rows = records
      before = Marshal.dump(rows)
      driver = TournamentNativeDriver.new
      parent, instance = nil, nil
      reads, calls, alerts = 0, [], []
      returning, counts = false, nil
      chain = []
      injections = Hash.new(0)
      reenter = ->(phase) do
        injections[phase] += 1
        2.times do
          ['Check selected operation', 'Refresh', 'Back'].each { |label| button(parent, label).press }
          parent.fields.first.trigger(:select)
          parent.game_room_hotkey_action(1).call
          instance.run
        end
        assert(calls.empty? && reads == 1 && alerts.empty?, "OPS-2 #{phase}: pomoc wykonała callback rodzica")
        assert(parent.instance_variable_get(:@wait), "OPS-2 #{phase}: pomoc zamknęła rodzica")
      end
      native_tick = driver.method(:tick)
      driver.define_singleton_method(:tick) do |form|
        native_tick.call(form)
        if form.is_a?(GameRoomUI::Form) && form.fields.first.header == 'Keyboard shortcuts' &&
            form.instance_variable_get(:@wait).nil?
          [:before_focus, :focus].each do |event|
            form.fields.first.on(event) { reenter.call("help_#{event}".to_sym) }
          end
        end
      end
      driver.press(HEADER, 40)
      driver.press(HEADER, 13) if origin == 1
      driver.step(HEADER) do |form|
        parent = form
        form.fields[1].index, form.fields[1].check = 7, 15
        [:before_focus, :focus].each do |event|
          form.fields[origin].on(event) do
            if returning
              chain << [event, form.index, form.fields.first.index]
              reenter.call(event)
            end
          end
        end
        target = form.fields[origin]
        native_focus = target.method(:focus)
        target.define_singleton_method(:focus) do |*arguments|
          if returning
            chain << [:control_focus, form.index, form.fields.first.index]
            reenter.call(:control_focus)
          end
          native_focus.call(*arguments)
        end
      end
      [13, 27].each do |close_key|
        driver.step(HEADER) do |form|
          original_text = form.fields[1].text.dup
          chain.clear
          returning = true
          form.game_room_hotkey_action(1).call
          returning = false
          speech = SpeechOutput.calls.drop(counts[0]).map(&:first)
          braille = NVDA.calls.drop(counts[1]).map(&:first)
          puts "CHECK OPS pojedynczy F1 #{origin}/#{close_key}: #{ {speech: speech.length, braille: braille.length, chain: chain}.inspect }"
          assert(speech.length == 1 && braille.length == 1, 'OPS F1 musi ogłosić rodzica raz w mowie i brajlu')
          assert_equal([:before_focus, :control_focus, :focus].map { |event| [event, origin, 1] }, chain)
          assert_equal(origin, form.index)
          assert_equal(1, form.fields.first.index)
          assert_equal(original_text, form.fields[1].text)
          assert(form.fields[1].text.include?(rows.last['id']), 'Pomoc zmieniła szczegóły zaznaczonego ID')
          assert_equal([7, 15], [form.fields[1].index, form.fields[1].check])
          (speech + braille).each do |value|
            expected_header = origin.zero? ? HEADER : 'Operation details'
            expected_item = origin.zero? ? 'Registration for tournament 12' : rows.last['id']
            wrong_item = origin.zero? ? 'Registration for tournament 11' : rows.first['id']
            assert(value.start_with?(expected_header) && value.include?(expected_item) && !value.include?(wrong_item),
              'Nawet pierwsza prezentacja po pomocy musi dotyczyć oryginalnego pola i ID B')
          end
        end
        driver.step('Keyboard shortcuts') do |form|
          assert(form.fields.first.text.include?('never sends the request again'), 'Pominięto wspólną pomoc F1')
          form.game_room_hotkey_action(1).call
          reenter.call(:modal)
          parent.fields.first.index = 0
          parent.fields.first.trigger(:move)
          parent.index = 4
        end
        driver.step('Keyboard shortcuts', [close_key]) do
          counts = [SpeechOutput.calls.length, NVDA.calls.length]
        end
      end
      driver.on_resume = ->(form) do
        next if form.equal?(parent)
        reenter.call(:resume)
        parent.fields.first.index = 0
        parent.fields.first.trigger(:move)
        parent.index = 4
      end
      # Świadome akcje po obu zamknięciach pomocy potwierdzają zwolnienie busy.
      driver.step(HEADER) do |form|
        button(form, 'Check selected operation').press
        assert_equal([rows.last['id']], calls)
        button(form, 'Refresh').press
        assert_equal(2, reads)
      end
      driver.step(HEADER, [27])
      instance = screen(load: -> { reads += 1; rows }, reconcile: ->(id) { calls << id; nil },
        alert: ->(message) { alerts << message })
      instance.run
      instance.run
      driver.finish
      assert_equal(2, reads)
      assert_equal([rows.last['id']], calls)
      assert_equal(before, Marshal.dump(rows))
      [:modal, :resume, :before_focus, :control_focus, :focus, :help_before_focus, :help_focus].each do |phase|
        assert(injections[phase] >= 2, "Nie wykonano powtórzeń granicy #{phase}")
      end
      assert_equal(3, driver.forms.length)
      puts "PASS OPS-2: pole=#{origin}; F1/Enter/Escape, pojedyncza mowa/brajl, pełny łańcuch fokusu i reentry; świadome Check/Refresh/Back po pomocy"
    end
  end

  def run
    restored_selection
    guarded_help
    rows = records
    before = JSON.generate(rows)
    driver = TournamentNativeDriver.new
    driver.press(HEADER, 40)
    driver.press(HEADER, 13)
    driver.step(HEADER) do |form|
      assert_equal(1, form.index)
      assert_equal(1, form.fields.first.index)
      assert(form.fields[1].text.include?(rows.last['id']), 'Podgląd nie dotyczy wskazanego ID')
      assert(SpeechOutput.calls.last.first.include?('Operation details'), 'Nie ogłoszono fokusu szczegółów')
    end
    driver.step(HEADER, [27])
    screen(load: -> { rows }).run
    driver.finish
    assert_equal(before, JSON.generate(rows))
    puts 'PASS Enter otwiera tylko szczegóły wskazanej operacji; brak wysyłki i zmian wejścia'

    driver = TournamentNativeDriver.new
    active_form = nil
    calls = []
    loads = 0
    confirmed = JSON.parse(JSON.generate(rows.last))
    confirmed['status'] = 'confirmed'
    confirmed['revision'] = 3
    confirmed['evidence'] = {'record_ids' => [15]}
    GameRoomTournaments::Publication::Data.freeze_tree(confirmed)
    load = -> do
      loads += 1
      loads == 1 ? rows : nil
    end
    reconcile = ->(id) do
      calls << id
      button(active_form, 'Check selected operation').trigger(:press)
      button(active_form, 'Refresh').trigger(:press)
      button(active_form, 'Back').trigger(:press)
      # Modalny callback może pozostawić fokus na innym polu rodzica.
      active_form.index = 4
      confirmed
    end
    driver.press(HEADER, 40)
    driver.press(HEADER, 9)
    driver.press(HEADER, 9)
    driver.step(HEADER, [32]) { |form| active_form = form }
    driver.step(HEADER) do |form|
      assert_equal(2, form.index)
      assert_equal(1, form.fields.first.index)
      assert(form.fields.first.options[1].end_with?('; confirmed'), 'Potwierdzenie ukryto po błędzie odświeżenia')
      assert(form.fields[1].text.include?(confirmed['id']), 'Zmieniono ID szczegółów po sprawdzeniu')
      assert(SpeechOutput.calls.last.first.start_with?('Check selected operation'), 'Brak mowy przywróconego przycisku')
      assert(NVDA.calls.last.first.start_with?('Check selected operation'), 'Brak brajla przywróconego przycisku')
    end
    driver.on_resume = ->(form) { button(form, 'Check selected operation').trigger(:press) }
    driver.step(HEADER, [27])
    screen(load: load, reconcile: reconcile).run
    driver.finish
    assert_equal([rows.last['id']], calls)
    assert_equal(2, loads)
    assert_equal(before, JSON.generate(rows))
    puts 'PASS sprawdzenie jednego ID bez reentry; wynik zachowany po nil odczytu, fokus/mowa/brajl przy przycisku'

    driver = TournamentNativeDriver.new
    reads = 0
    load = -> do
      reads += 1
      reads == 1 ? rows : rows.reverse
    end
    driver.press(HEADER, 40)
    3.times { driver.press(HEADER, 9) }
    driver.press(HEADER, 13)
    driver.step(HEADER) do |form|
      assert_equal(0, form.fields.first.index)
      assert_equal(3, form.index)
      assert(form.fields[1].text.include?(rows.last['id']), 'Odświeżenie zmieniło wybraną operację')
    end
    driver.step(HEADER, [27])
    screen(load: load).run
    driver.finish
    puts 'PASS odświeżenie zachowuje ID mimo zmiany kolejności'

    expected = {
      'prepared' => 'prepared; not confirmed', 'attempted' => 'attempted; not confirmed',
      'confirmed' => 'confirmed', 'outside_window' => 'outside the registration window',
      'conflict' => 'conflict; no further submission', nil => 'attempted; not confirmed'
    }
    expected.each do |status, state_label|
      driver = TournamentNativeDriver.new
      reads, calls = 0, []
      load = -> { reads += 1; reads == 1 ? rows : nil }
      action = ->(id) { calls << id; status && TournamentPublicUI.record(status) }
      driver.press(HEADER, 9)
      driver.press(HEADER, 9)
      driver.press(HEADER, 13)
      driver.step(HEADER) do |form|
        assert_equal('Registration for tournament 11; ' + state_label, form.fields.first.options.first)
        assert_equal(2, form.index)
      end
      driver.step(HEADER, [27])
      screen(load: load, reconcile: action).run
      driver.finish
      assert_equal([rows.first['id']], calls)
    end
    puts 'PASS wszystkie stany oraz nil; niepotwierdzone operacje nie są przedstawiane jako potwierdzone'

    driver = TournamentNativeDriver.new
    screen(load: -> { nil }).run
    driver.finish
    assert_equal([], driver.forms)
    puts 'PASS początkowy błąd odczytu nie otwiera pustej listy'

    driver = TournamentNativeDriver.new
    reads = 0
    load = -> { reads += 1; reads == 1 ? rows : [] }
    3.times { driver.press(HEADER, 9) }
    driver.press(HEADER, 13)
    driver.step(HEADER) { |form| assert_equal([], form.fields.first.options) }
    driver.step(HEADER, [27])
    screen(load: load).run
    driver.finish
    puts 'PASS rzeczywisty pusty odczyt usuwa zakończoną listę bez wywołania sprawdzania'
  end
end
TournamentOperationsScreenTest.run
