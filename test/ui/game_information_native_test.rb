require_relative '../support/host_source'
require_relative '../support/duck_challenge_native'
require_relative '../support/localization'
require_relative '../support/dealt_card_games'
require_relative '../../lib/game_screen'

table = GameRoomTest::DealtCardTable.new('hearts',count:4,options:{'score_limit'=>30},seed:17)
table.events.each_with_index { |event,index| event['created_at']=1001+index }
table.refresh
game, replay, repo = table.game, table.replay, table.repository
session = table.session.merge('created_at'=>100,'__server_started_at'=>1000)
viewer = replay.current_player
tick = 0.0

%w[en pl cs es ru].each do |language|
  GameRoomTestLocalization.use_language(language)
  Session.name = viewer
  driver = DuckChallengeNativeDriver.new
  layout = GameRoomLayout::Screen.new(view_spec:game.game_view_spec(replay,viewer),
    chat_text:'Keep this draft.', history_items:replay.history.map(&:text), user_items:replay.players)
  screen = GameScreen.allocate
  screen.instance_variable_set(:@game,game)
  screen.instance_variable_set(:@repository,repo)
  screen.instance_variable_set(:@session,session)
  tick = 0.0
  clock = GameRoomSessionClock.new(sample:->{1100},elapsed:->{tick},wall:->{1100})
  screen.instance_variable_set(:@action_clock,clock)
  actions = []
  shortcuts = game.game_shortcuts(replay,viewer)
  GameRoomShortcutBindings.bind(layout.form,layout.shortcut_fields,shortcuts,
    consume:->(*) { EltenAPI::KeyboardState.clear_current_frame }) do |shortcut|
    result = screen.send(:activate_game_shortcut,shortcut,layout.surface,replay:replay)
    actions << result if result.is_a?(GameSurfaces::Action)
  end
  layout.form.index = layout.form.fields.index(layout.surface.fields.first)
  layout.form.focus
  driver.frame(layout.form)
  SpeechOutput.reset
  driver.frame(layout.form,driver.tap(0x54,modifiers:[0x11]),characters:'t')
  expected = GameRoomDuration.text('game',game:game,replay:replay,session:session,repository:repo,now:200)
  assert(SpeechOutput.calls.map(&:first) == [expected], "#{language}: Ctrl+T does not speak game duration exactly once")
  assert(language=='en' || !expected.start_with?('Game duration:'), 'Duration is untranslated')
  if language != 'en'
    assert(!game.move_error(:hearts_opening_club).include?('two of clubs'), 'Opening-card refusal is untranslated')
    assert(!game.move_error(:hearts_first_trick).start_with?('You cannot'), 'First-trick refusal is untranslated')
    assert(!game.move_error(:hearts_not_broken).start_with?('You cannot'), 'Unbroken-hearts refusal is untranslated')
  end
  driver.frame(layout.form)
  SpeechOutput.reset
  driver.frame(layout.form,driver.tap(0x54,modifiers:[0x11,0x10]),characters:'t')
  expected = GameRoomDuration.text('round',game:game,replay:replay,session:session,repository:repo,now:200)
  assert(SpeechOutput.calls.map(&:first) == [expected], 'Ctrl+Shift+T uses the match start instead of the deal')
  # The original binding remains installed: the readout must still advance.
  tick = 61.0
  driver.frame(layout.form)
  SpeechOutput.reset
  driver.frame(layout.form,driver.tap(0x54,modifiers:[0x11]),characters:'t')
  expected = GameRoomDuration.text('game',game:game,replay:replay,session:session,repository:repo,now:261)
  assert(SpeechOutput.calls.map(&:first) == [expected], 'Prepared shortcuts freeze the duration at form construction')
  driver.frame(layout.form)
  SpeechOutput.reset
  driver.frame(layout.form,driver.tap(0x53),characters:'s')
  score = shortcuts.find { |shortcut| shortcut.key=='s' && shortcut.modifiers.empty? }.message
  assert(SpeechOutput.calls.map(&:first) == [score] && score.end_with?(game.score_target_text(replay)), 'S duplicates speech or omits the trailing target')
  assert(actions.empty?, 'An informational shortcut submitted a move')
  assert(layout.surface.fields.first.equal?(layout.form.fields[layout.form.index]), 'Readout changed focus')
  layout.form.index = layout.form.fields.index(layout.chat)
  driver.frame(layout.form)
  SpeechOutput.reset
  driver.frame(layout.form,driver.tap(0x54,modifiers:[0x11]),characters:'t')
  assert(SpeechOutput.calls.map(&:first) == [expected], 'Modified informational keys stopped working while typing')
  assert(layout.chat.text.include?('Keep this draft.'), 'Readout cleared the chat draft')
  driver.frame(layout.form)
  SpeechOutput.reset
  driver.frame(layout.form,driver.tap(0x54),characters:'t')
  assert(SpeechOutput.calls.map(&:first).none? { |text| text == expected } && actions.empty?, 'Ordinary typed T invokes duration or submits a move')
end

GameRoomTestLocalization.use_language('en')
require_relative '../../lib/game_simulation'
%w[quiz categories war].each do |id|
  consumer = GameRoomGames::CATALOG.build(id)
  env = GameRoomSimulation::Environment.new_game(game:consumer,players:%w[Alice Bob],seed:7)
  keys = consumer.game_shortcuts(env.replay,'Alice')
  times = keys.select { |key| key.payload['duration_scope'] }
  assert(times.size == (id == 'categories' ? 0 : 2), "#{id}: wrong duration-key exclusion")
  old = keys.find { |key| key.key == 't' && key.modifiers == (id == 'categories' ? [:control] : [:control,:alt].sort) }
  assert(old && !old.payload['duration_scope'], "#{id}: existing readout disappeared")
  driver = DuckChallengeNativeDriver.new
  layout = GameRoomLayout::Screen.new(view_spec:consumer.game_view_spec(env.replay,'Alice'),history_items:[],user_items:env.replay.players)
  screen = GameScreen.allocate
  screen.instance_variable_set(:@game,consumer)
  GameRoomShortcutBindings.bind(layout.form,layout.shortcut_fields,keys,
    consume:->(*) { EltenAPI::KeyboardState.clear_current_frame }) do |key|
    screen.send(:activate_game_shortcut,key,layout.surface,replay:env.replay)
  end
  layout.form.index = layout.form.fields.index(layout.surface.fields.first)
  layout.form.focus
  driver.frame(layout.form)
  SpeechOutput.reset
  driver.frame(layout.form,driver.tap(0x54,modifiers:id=='categories' ? [0x11] : [0x11,0x12]),characters:'t')
  assert(SpeechOutput.calls.map(&:first) == [old.message], "#{id}: native modified key no longer reaches its original readout")
end
puts 'PASS native Ctrl+T/Ctrl+Shift+T/S, dynamic readout without rebinding, one speech, focus/chat safety in five languages, Quiz/War remap and Countries exception'
