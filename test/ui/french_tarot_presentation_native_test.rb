require_relative '../support/duck_challenge_native'
require_relative '../support/french_tarot'
require_relative '../../lib/game_screen'

class TarotChoiceDriver < DuckChallengeNativeDriver
  attr_reader :modal, :speech

  def initialize(key, index)
    super()
    @key, @index, @frames = key, index, 0
  end

  def tick(form)
    @frames += 1
    raise 'Tarot contract dialog did not close' if @frames > 8
    if form.instance_variable_get(:@wait)
      @modal ||= form
      raise 'Contract opened another modal' unless @modal.equal?(form)
      list = form.fields.first
      raise 'Contract did not use the native list' unless list.instance_of?(ListBox)
      @speech ||= SpeechOutput.calls.dup
      list.index = @index
      snapshot(tap(@key), [])
    else
      snapshot([], [])
    end
  end
end

%w[en pl cs es ru].each do |language|
  GameRoomLocalization.boot(settings: {'interface_language' => language, 'known_languages' => [language]}, host_language: language)
  env = FrenchTarotFixture.match
  replay, game = env.replay, env.game
  shortcut = game.game_shortcuts(replay, replay.current_player).find { |item| item.key == 'b' }
  raise 'Current bidder lacks B' unless shortcut && shortcut.kind == :choice
  raise 'Bids are not in increasing order' unless shortcut.choices.map(&:value) == %w[pass petite garde garde_sans garde_contre]
  raise 'Non-bidder may bid' if game.game_shortcuts(replay, 'observer').any? { |item| item.key == 'b' }
  screen = GameScreen.allocate
  [0x0D, 0x1B].each do |key|
    SpeechOutput.reset
    driver = TarotChoiceDriver.new(key, 1)
    action = screen.send(:choice_shortcut_action, shortcut)
    raise 'Prompt was repeated or missing' unless driver.speech.one? && driver.speech.first.first.include?(shortcut.prompt)
    raise 'Native dialog remained active' if driver.modal.instance_variable_get(:@wait)
    if key == 0x1B
      raise 'Escape submitted a bid' unless action.nil?
    else
      raise 'B lost its contract payload' unless action['action'] == 'tarot_bid' && action['choice'] == 'petite' && action.source == 'shortcut:b'
    end
  end
  expected_half = language == 'en' ? '-0.5' : '-0,5'
  raise 'Negative half-point formatting is incorrect' unless game.send(:tarot_points, -1) == expected_half
  actor = replay.current_player
  pass = game.legal_actions(replay, actor).find { |action| action['choice'] == 'pass' }
  raise 'Pass was refused' unless env.step(pass) == :ok
  if language == 'pl'
    raise 'Bidding was described as skipping a turn' unless env.replay.history.last.text == "#{actor} pasuje."
  end
end
$activecontrols = []
puts 'PASS Tarot native B: five languages, single prompt, bid identity, Escape, turn scope and half-point formatting'
