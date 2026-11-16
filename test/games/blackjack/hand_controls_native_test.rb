require_relative '../../support/host_source'
require_relative '../../support/duck_challenge_native'
require_relative '../../support/localization'
require_relative '../../../games/blackjack'
require_relative '../../support/blackjack'
require_relative '../../../lib/game_screen'

def blackjack_controls(game, replay, viewer = 'Alice')
  Session.name = viewer
  driver = DuckChallengeNativeDriver.new
  layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay, viewer),
    history_items: ['Keep the history.'], user_items: replay.players)
  actions = []
  layout.surface.on_action { |action| actions << action }
  screen = GameScreen.allocate
  screen.instance_variable_set(:@game, game)
  GameRoomShortcutBindings.bind(layout.form, layout.shortcut_fields, game.game_shortcuts(replay, viewer),
    consume: ->(*) { EltenAPI::KeyboardState.clear_current_frame }) do |shortcut|
    result = screen.send(:activate_game_shortcut, shortcut, layout.surface, replay: replay)
    actions << result if result.is_a?(GameSurfaces::Action)
  end
  layout.form.index = layout.form.fields.index(layout.surface.fields.first)
  SpeechOutput.reset
  layout.form.focus
  [driver, layout, actions]
end

game = BlackjackChecksSupport::FixedDeck.new
game.first_cards = %w[5C 8C 9D 7S 6D 7H 3C 2D TC]
repo = BlackjackChecksSupport::Repository.new(%w[Alice Bob])
session = {'options'=>JSON.generate(game.new_game_options('round_limit'=>1))}
events = [BlackjackChecksSupport.event(1, 'Alice', 'ante'),
  BlackjackChecksSupport.event(2, 'Alice', 'bet', 'check|0'),
  BlackjackChecksSupport.event(3, 'Bob', 'bet', 'check|0'),
  BlackjackChecksSupport.event(4, 'Alice', 'deal', "1|#{'0' * 32}")]
replay = game.replay(session, events, repo)
assert(replay.state[:phase] == :playing && replay.current_player == 'Alice', 'Fixture did not reach normal card play')

%w[en pl cs es ru].each do |language|
  GameRoomTestLocalization.use_language(language)
  driver, layout, actions = blackjack_controls(game, replay)
  surface, form = layout.surface, layout.form
  assert(surface.fields.length == 1, "#{language}: Blackjack retains a separate actions field")
  control = surface.fields.first
  cards = surface.displayed_hand_cards('hand')
  assert(cards.map(&:id) == %w[0:5C 0:7S], 'The combined field changed actual hand order')
  assert(control.options == cards.map(&:label), 'The hand contains redundant action rows')
  dealer = GameRoomContent.utf8(game.send(:playing_card_label, '0:9D'))
  hidden = GameRoomContent.utf8(game.send(:playing_card_label, '0:7H'))
  header = GameRoomContent.utf8(control.header)
  assert(header.lines.first.include?(dealer) && !header.include?(hidden), 'Dealer is not first or the hole card was exposed')
  assert(header.lines.last.include?('12'), 'The current hand total is missing below the dealer')
  spoken = SpeechOutput.calls.map(&:first).join("\n")
  assert(spoken.include?(dealer) && spoken.index(dealer) < spoken.index(GameRoomContent.utf8(cards.first.label)),
    "#{language}: focus did not read dealer information before the hand")
  enter = GameRoomContent.utf8(GameRoomLocalization.translate('Enter'))
  assert(GameRoomContextHelp.game_field_tips([control]).any? { |tip| tip.include?(enter) }, 'F1 omits the default Enter action')

  driver.frame(form)
  SpeechOutput.reset
  driver.frame(form, driver.tap(0x20), characters:' ')
  assert(actions.map(&:name) == ['hit'], 'Space did not produce exactly one normal draw')
  status, = game.action_for(actions.last, replay, 'Alice')
  assert(status == :ok, 'Space bypassed or failed the normal game validator')
  after = game.replay(session, events + [BlackjackChecksSupport.event(5, 'Alice', 'hit')], repo)
  surface.update_spec(game.surface_spec(after, 'Alice'))
  assert(surface.fields.first.equal?(control) && surface.displayed_hand_cards('hand').map(&:id) == %w[0:5C 0:7S 0:3C],
    'Drawing rebuilt the field or lost acquisition order')
  assert(surface.displayed_hand_cards('hand')[control.index].id == '0:3C', 'The last drawn physical card lost the cursor')
  assert(SpeechOutput.calls.empty?, 'Quiet hand refresh repeated the dealer or total')

  actions.clear
  driver.frame(form)
  driver.frame(form, driver.tap(0x0d))
  assert(actions.map(&:name) == ['stand'], 'Enter did not stand once on the current hand')
  assert(game.action_for(actions.last, after, 'Alice').first == :ok, 'Enter bypassed or failed normal stand validation')
  assert(game.action_for(actions.last, after, 'Bob').first == :not_your_turn, 'Another player can stand for the current hand')
  surface.action_guard = -> { false }
  actions.clear
  driver.frame(form)
  driver.frame(form, driver.tap(0x0d))
  assert(actions.empty?, 'Enter bypassed the shared pending-operation action guard')
  surface.action_guard = nil

  form.index = form.fields.index(layout.chat)
  layout.chat.set_text('Keep my draft.')
  driver.frame(form, driver.tap(0x20), characters:' ')
  driver.frame(form)
  driver.frame(form, driver.tap(0x0d))
  assert(actions.empty? && layout.chat.text.include?('Keep my draft.'), 'Card controls captured chat input')
  pressed = 0
  layout.voice_button.on(:press) { pressed += 1 }
  form.index = form.fields.index(layout.voice_button)
  driver.frame(form)
  driver.frame(form, driver.tap(0x0d))
  assert(actions.empty? && pressed == 1, 'Enter on a table button changed the Blackjack hand')
end

GameRoomTestLocalization.use_language('en')
extended = {'options'=>JSON.generate(game.new_game_options('variant'=>'extended', 'round_limit'=>1))}
game.first_cards = %w[8C 5C 9D 8D 7S 7H 2C 3C 4C]
pair = game.replay(extended, events, repo)
driver, layout, actions = blackjack_controls(game, pair)
shortcuts = game.game_shortcuts(pair, 'Alice')
assert(shortcuts.any? { |key| key.key == 'd' && key.action_name == 'double' }, 'Extended doubling became inaccessible')
assert(shortcuts.any? { |key| key.key == 'p' && key.action_name == 'split' }, 'Extended splitting became inaccessible')
driver.frame(layout.form, driver.tap('D'.ord))
assert(actions.map(&:name) == ['double'] && game.action_for(actions.first, pair, 'Alice').first == :ok,
  'Double does not use the normal action')
actions.clear
driver.frame(layout.form)
driver.frame(layout.form, driver.tap('P'.ord))
assert(actions.map(&:name) == ['split'] && game.action_for(actions.first, pair, 'Alice').first == :ok, 'Split does not use the normal action')
split_events = events + [BlackjackChecksSupport.event(5, 'Alice', 'split')]
split = game.replay(extended, split_events, repo)
first = game.surface_spec(split, 'Alice')
next_hand = game.replay(extended, split_events + [BlackjackChecksSupport.event(6, 'Alice', 'stand')], repo)
second = game.surface_spec(next_hand, 'Alice')
assert(first.zones.length == 1 && second.zones.length == 1 && first.zones.first.hand_epoch != second.zones.first.hand_epoch,
  'Split hands share an epoch or restore a second field')
assert(second.zones.first.header.include?('2 of 2'), 'The second split hand cannot be identified')
assert(game.game_shortcuts(split, 'Alice').none? { |key| %w[double split].include?(key.action_name) }, 'Unavailable split/double keys remain')
driver, layout, actions = blackjack_controls(game, next_hand)
driver.frame(layout.form, driver.tap(0x0d))
assert(actions.map(&:name) == ['stand'] && game.action_for(actions.first, next_hand, 'Alice').first == :ok,
  'Enter cannot stand on the second split hand')

social_session = {'options'=>JSON.generate(game.new_game_options('variant'=>'social', 'round_limit'=>1))}
awaiting_deal = game.replay(social_session, events.first(3), repo)
assert(awaiting_deal.state[:phase] == :awaiting_deal, 'Social fixture did not reach manual dealing')
driver, layout, actions = blackjack_controls(game, awaiting_deal)
assert(layout.surface.fields.length == 1, 'Waiting for social dealing restores a separate field')
driver.frame(layout.form, driver.tap('D'.ord))
assert(actions.map(&:name) == ['deal'], 'D stopped dealing in social blackjack')
social = game.replay(social_session, events, repo)
actor = social.current_player
driver, layout, actions = blackjack_controls(game, social, actor)
assert(layout.surface.fields.length == 1 && layout.surface.fields.first.header.include?('no house hand'),
  'Social play shows a fictitious dealer hand or a second field')
assert(game.game_shortcuts(social, actor).none? { |key| %w[double split deal].include?(key.action_name) },
  'Social play exposes extended actions or lets the player deal twice')
driver.frame(layout.form, driver.tap(0x0d))
assert(actions.map(&:name) == ['stand'] && game.action_for(actions.first, social, actor).first == :ok,
  'Social Enter does not keep the current total')

_, observer, observer_actions = blackjack_controls(game, pair, 'Watcher')
assert(observer.surface.fields.length == 1 && observer.surface.displayed_hand_cards('hand').nil? && observer_actions.empty?,
  'Observer acquired another player’s hand or action')
assert(game.game_shortcuts(pair, 'Watcher').none? { |key| %w[hit double split].include?(key.action_name) }, 'Observer has play keys')
puts 'PASS Blackjack native controls: one field, dealer before hand, hidden hole card, Space/Enter, total/draw focus, quiet refresh, guarded actions, chat/buttons, double/split hands, social dealing and observers in five languages; no live accounts or physical keyboard'
