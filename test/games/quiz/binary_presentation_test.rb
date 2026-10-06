require_relative "../../support/binary_rules_load"

game = EltenGameRoom::GAME_REGISTRY.build('quiz')
expected = {'pl' => 'Wysłano odpowiedź.', 'en' => 'Answer sent.',
  'cs' => 'Odpověď odeslána.', 'es' => 'Respuesta enviada.',
  'ru' => 'Ответ отправлен.', 'fallback' => 'Answer sent.'}
expected.each do |language, text|
  GameRoomTestLocalization.use_language(language)
  replay = GameRoomGames::Replay.new(players: %w[Alice Bob], state: {
    phase: :answering, deadline: 100, round: 1, position: 1,
    players: %w[Alice Bob], commitments: {'Alice' => 'saved'}
  })
  spec = game.surface_spec(replay, 'Alice')
  raise "Bad translated status: #{language}" unless spec.value == text && spec.prompt.empty?
  field = GameSurfaces::QuestionSurface.new(spec).fields.first
  raise "Bad control text: #{language}" unless field.text == text && (field.text + ' — słowo').valid_encoding?
  replay.state[:phase] = :revealing
  spec = game.surface_spec(replay, 'Alice')
  raise 'Redundant revealing announcement' unless spec.value.empty? && spec.prompt.empty?
  entry = GameRoomChangelog::ENTRIES.find { |item| item.build == 245 }
  raise 'Wrong release' unless entry&.version == '2.0.4.6' && entry.changes.length == 3
  entry.changes.each do |source|
    translated = GameRoomLocalization.translate(source)
    raise "Untranslated release note: #{language}" if !%w[en fallback].include?(language) && translated == source
    raise 'Invalid release encoding' unless (translated + ' — słowo').valid_encoding?
  end
end
raise 'Wrong runtime version' unless EltenGameRoom::GAME_ROOM_VERSION == '2.0.4.6' && EltenGameRoom::GAME_ROOM_BUILD_ID == 245
sound = BinaryRulesLoad.read(File.join(BinaryRulesLoad::ROOT, 'Audio/quiz_wrong_answer.opus'))
raise 'Missing Opus sound' unless sound.start_with?('OggS') && sound.byteslice(0, 128).include?('OpusHead')
puts 'PASS binary Quiz status and release 245 in PL/EN/CS/ES/RU/fallback, controls and packaged sound'
