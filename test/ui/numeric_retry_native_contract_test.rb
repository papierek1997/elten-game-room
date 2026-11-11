require_relative '../support/audio_tutorial_native'
require EltenTestHost.file('src/ui/dialogs.rb')
require_relative '../../games/poker'
require_relative '../../games/spades'
require_relative '../../games/monopoly'
require_relative '../../games/biblios'
require_relative '../../games/roulette'
require_relative '../../lib/game_screen'

# Keep the native SpeechSequence and EditBox focus logic. Only the output
# device is replaced, using the host's non-indexed output implementation.
module SpeechOutput
  def self.speak_sequence(sequence)
    speak_text(sequence.text, method: 1, interrupt: true)
  end
end

module NumericNativeCapture
  def initialize(*arguments, **options)
    super
    ($numeric_native_fields ||= []) << self
  end
end
EditBox.prepend(NumericNativeCapture)

def numeric_frame(keys)
  state = "\0" * 256
  keys.each { |key| state.setbyte(key, 0x80) }
  previous = $numeric_native_keys || []
  events = (previous - keys).map { |key| [key, false] } + (keys - previous).map { |key| [key, true] }
  EltenAPI::KeyboardState.update(raw_state: state, events: events, now: Process.clock_gettime(Process::CLOCK_MONOTONIC),
    pressed_implies_held: false, synthesize_repeats: false)
  $numeric_native_keys = keys
  $input_frame_serial = $input_frame_serial.to_i + 1
  $keyboard_state_frame_serial = $input_frame_serial
  $keyboard_state_frame_thread = Thread.current
  $activecontrols = []
end

def replay_for(state)
  GameRoomGames::Replay.new(players: state[:players], state: state, current_player: state[:current_player],
    accepted_events: [], history: [])
end

cases = []
%w[holdem draw].each do |variant|
  game = GameRoomGames::Poker.new
  state = game.send(:initial_state, %w[Alice Bob], game.normalize_options('variant' => variant))
  state.update(phase: :betting, current_player: 'Alice', current_bet: 20, min_raise: 10,
    street_bets: {'Alice' => 0, 'Bob' => 20}, contributions: {'Alice' => 0, 'Bob' => 20})
  cases << ["Poker #{variant}", game.custom_game_shortcuts(replay_for(state), 'Alice').find { |item| item.key == 'r' }]
end

game = GameRoomGames::Spades.new
players = %w[Alice Bob Carol]
options = game.default_options
state = game.send(:initial_state, players, options, GameRoomGames::Spades::Scoring.new(players, options))
state.update(phase: :bidding, current_player: 'Alice')
cases << ['Spades', game.game_shortcuts(replay_for(state), 'Alice').find { |item| item.key == 'b' }]

game = GameRoomGames::Monopoly.new
state = game.send(:initial_state, players, game.default_options)
state.update(phase: :auction, current_player: 'Alice', auction_bid: 10, auction_property: 1)
cases << ['Monopoly', game.custom_game_shortcuts(replay_for(state), 'Alice').find { |item| item.kind == :number_input }]

game = GameRoomGames::Biblios.new
state = game.send(:initial_state, players, game.default_options)
state.update(phase: :auction, current_player: 'Alice', card: 'o1')
state[:hands]['Alice'] = %w[ba bb bc]
cases << ['Biblios', game.custom_game_shortcuts(replay_for(state), 'Alice').find { |item| item.kind == :number_input }]

game = GameRoomGames::Roulette.new
repository = Struct.new(:players) { def players_for(_session); players; end }.new(%w[Alice Bob])
replay = game.replay({'options' => JSON.generate(game.default_options)}, [], repository)
cases << ['Roulette Enter', game.surface_action_shortcut(game.legal_actions(replay, 'Alice').first, replay, 'Alice')]

cases.each do |label, shortcut|
  assert(shortcut&.kind == :number_input, "#{label}: actual game has no numeric shortcut")
  allowed = shortcut.allowed_values
  valid = allowed.first
  invalid = (allowed.is_a?(Range) ? allowed.end : allowed.max) + 1
  screen = GameScreen.allocate
  screen.define_singleton_method(:alert) { |*| raise 'Numeric error used an interrupting alert' }
  fields_before = $numeric_native_fields.to_a.length
  seen = []
  previous_field = nil
  SpeechOutput.reset
  driver = Object.new
  $native_tutorial_driver = driver
  frames = 0
  driver.define_singleton_method(:tick) do |form|
    frames += 1
    raise "#{label}: numeric dialog did not finish" if frames > 30
    unless form.instance_variable_get(:@wait)
      numeric_frame([]) # Constructor/resume pumps are not new input turns.
      next
    end
    field = $numeric_native_fields.last
    if field.equal?(previous_field)
      numeric_frame([]) # The host's post-submit frame clears the old Enter.
      next
    end
    previous_field = field
    index = seen.length
    assert(index < 2, "#{label}: extra retry dialog")
    initial = index.zero? ? (shortcut.default_value&.to_i&.to_s || '') : invalid.to_s
    assert(field.text == initial, "#{label}: retry lost the entered value")
    assert([field.index, field.check].minmax == [0, initial.length], "#{label}: initial/retry value is not selected") unless initial.empty?
    assert(screen.send(:dialog_opened), "#{label}: the actual host dialog was not opened")
    assert(field.header.end_with?(shortcut.prompt), "#{label}: field no longer explains the requested value")
    assert(SpeechOutput.calls.count { |call| call.first.include?(field.header) } == 1,
      "#{label}: amount field was announced more than once: #{SpeechOutput.calls.inspect}")
    if index == 1
      assert(field.header.include?('Allowed values:') && SpeechOutput.calls.any? { |call| call.first.include?('Allowed values:') },
        "#{label}: native field focus did not read the validation error")
    end
    seen << field
    field.set_text(index.zero? ? invalid.to_s : valid.to_s)
    numeric_frame([0x0D])
  end
  action = screen.send(:number_shortcut_action, shortcut)
  assert(action.payload == shortcut.payload.merge(shortcut.value_key => valid), "#{label}: retry changed payload or value")
  assert(action.name == shortcut.action_name && action.source == "shortcut:#{shortcut.key}", "#{label}: action identity changed")
  assert($numeric_native_fields.length - fields_before == 2 && !screen.send(:dialog_opened), "#{label}: extra or leaked native dialog")

  # Escape is a cancellation, not a zero bid. It must not propagate into the
  # underlying game screen as a second Escape or a pending submit key.
  frames = 0
  driver.define_singleton_method(:tick) do |form|
    frames += 1
    raise "#{label}: Escape did not close the numeric dialog" if frames > 15
    numeric_frame(form.instance_variable_get(:@wait) ? [0x1B] : [])
  end
  assert(screen.send(:number_shortcut_action, shortcut).nil?, "#{label}: Escape submitted a number")
  assert(!screen.send(:dialog_opened), "#{label}: cancelled dialog stayed open")
  assert(!EltenAPI::KeyboardState.current.pressed[0x1B], "#{label}: Escape leaked out of the numeric dialog")
  numeric_frame([])
end

# Compiled translations may be binary strings. Combining the error and the
# prompt must retain valid non-ASCII text rather than raise an encoding error.
shortcut = cases.first.last.dup
shortcut.prompt = 'Podbij o:'.b
shortcut.invalid_message = 'Nieprawidłowa kwota.'.b
screen = GameScreen.allocate
prompts, answers = [], ['999999999', '10']
screen.define_singleton_method(:number_shortcut_input) { |prompt, **_| prompts << prompt; answers.shift }
assert(screen.send(:number_shortcut_action, shortcut).payload['raise_by'] == 10, 'Binary translation prevented retry')
assert(prompts.last.encoding == Encoding::UTF_8 && prompts.last.include?('Nieprawidłowa kwota.'), 'Retry corrupted translated text')

puts 'PASS native numeric input: actual Poker variants, Spades, Monopoly and Biblios shortcuts, selected retry value, error spoken on focus, payload, Escape cleanup and binary translations'
