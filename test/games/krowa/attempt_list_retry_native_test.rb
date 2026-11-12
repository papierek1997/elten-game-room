require_relative '../../support/duck_challenge_native'
require_relative '../../support/assertions'
require_relative '../../../games/krowa'
require_relative '../../../games/krowa_support/attempt_list_view'
include GameRoomTest::Assertions

begin
  [:failed, :hidden].each do |unavailable|
    driver = DuckChallengeNativeDriver.new
    ranking = ListBox.new(['A', 'B'], header: 'Results', quiet: true)
    reads = []
    second_result = unavailable
    details = GameRoomGames::KrowaAttemptListView.new(GameRoomGames::Krowa.new,
      selection: -> { ranking.index }) do |identity|
      reads << identity
      identity.zero? ? {word: 'kot', words: %w[las kot]} : second_result
    end
    form = GameRoomUI::Form.new([ranking, details.field], quiet: true)
    form.focus
    press = lambda do |key, modifiers = []|
      driver.frame(form, modifiers.map { |modifier| [modifier, true] } +
        [[key, true, driver.raw([key] + modifiers)]], held: [key] + modifiers)
      driver.frame(form, [[key, false]] + modifiers.reverse.map { |modifier| [modifier, false] })
    end
    press.call(0x09)
    assert_equal(['las. 0', 'kot. 3'], details.field.options)
    press.call(0x28)
    assert_equal(1, details.field.index)
    press.call(0x09, [0x10])
    press.call(0x09)
    assert_equal([0], reads, 'Returning to an unchanged loaded result performed I/O')
    assert_equal(1, details.field.index, 'Returning to an unchanged result moved its cursor')

    press.call(0x09, [0x10])
    assert_equal(0, form.index, 'The native test did not return to the ranking')
    press.call(0x28)
    assert_equal(1, ranking.index, 'The native test did not select result B')
    press.call(0x09)
    assert_equal([], details.field.options, 'Unavailable B retained private attempts from A')
    assert_equal([0, 1], reads)
    press.call(0x09, [0x10])
    press.call(0x26)
    press.call(0x09)
    assert_equal(['las. 0', 'kot. 3'], details.field.options,
      "Returning from #{unavailable} B to A retained the unavailable presentation")
    assert_equal([0, 1, 0], reads)

    press.call(0x09, [0x10])
    press.call(0x28)
    press.call(0x09)
    second_result = {word: 'kot', words: ['kot']}
    press.call(0x09, [0x10])
    press.call(0x09)
    assert_equal(['kot. 3'], details.field.options, 'Unavailable selection was cached instead of retried')
    assert_equal([0, 1, 0, 1, 1], reads)
    press.call(0x09, [0x10])
    press.call(0x09)
    assert_equal([0, 1, 0, 1, 1], reads, 'Successful retry was not cached')
  end
  puts 'PASS native Krowa attempt details: A -> unavailable B -> A, same-selection retry, no stale disclosure, successful cursor reuse'
ensure
  $activecontrols = []
end
