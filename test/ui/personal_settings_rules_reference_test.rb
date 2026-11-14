require_relative '../support/rules_live_help'
require_relative '../support/localization'

languages = JSON.parse(File.read(File.expand_path('../../manifest.json', __dir__))).fetch('supported_languages')
languages.each do |language|
GameRoomTestLocalization.use_language(language)
players = %w[Alice Bob]
replay = GameRoomGames::Replay.new(players: players, state: nil, accepted_events: [], history: [])
expected_games = %w[audio_ball axel_pong darts krowa scrabble mania_pisania]
seen = []
EltenGameRoom::GAME_REGISTRY.ids.each do |id|
  game = EltenGameRoom::GAME_REGISTRY.build(id)
  layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(
    surface: GameSurfaces::PawnTrackSpec.new(id: 'status', header: game.name,
      items: [GameSurfaces::PawnTrackItem.new(id: 'move', label: 'Game field')])))
  GameRoomContextHelp.replace(layout.game_help_fields, ['T, read whose turn it is.'], source: :game)
  screen = GameScreen.allocate
  screen.instance_variable_set(:@game, game)
  screen.instance_variable_set(:@session, {'options' => JSON.generate(game.default_options)})
  screen.instance_variable_set(:@layout, layout)
  entry = GameRoomParticipantMenu.personal_settings_entry(game)
  [nil, GameRoomContextHelp.game_field_tips(layout.game_help_fields)].each do |snapshot|
    screen.instance_variable_set(:@rules_shortcut_snapshot, snapshot)
    documents = game.rule_book(options: game.default_options).documents.map(&:title)
    documents << GameRoomLocalization.translate('Audio tutorial') unless game.audio_tutorial_entries.empty?
    tips = read_live_shortcuts(screen, replay, expected_documents: documents)
    personal = tips.select { |tip| tip.start_with?('Ctrl+P') }
    assert(personal.length == (entry ? 1 : 0), "#{id}: wrong availability of Ctrl+P in live rules: #{tips.inspect}")
    if entry
      expected = GameRoomContextHelp.shortcut_tip(entry.help_key, entry.label)
      assert(personal == [expected], "#{id}: rules do not describe the actual settings command")
    end
    assert(tips.none? { |tip| tip.start_with?('Ctrl+I', 'Ctrl+R', 'Ctrl+Q') }, 'Room commands leaked into game rules')
  end
  seen << id if entry
end
assert(seen.sort == expected_games.sort, 'The audited personal-settings capabilities changed')
end
puts 'PASS live rules Ctrl+P: shared settings definitions, all games/languages, captured/current help, no duplicates or unavailable commands'
