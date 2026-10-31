require_relative "../../support/binary_rules_load"

game = EltenGameRoom::GAME_REGISTRY.build('quiz')
potter = GameRoomContent.registry.pack('quiz.harry_potter.books.pl')
raise 'Missing or eagerly loaded Harry Potter set' unless potter && !potter.verified?
raise 'Unexpected Harry Potter metadata' unless potter.title == 'Harry Potter' && potter.entry_count == 985
potter_questions = potter.data.fetch('questions')
raise 'Binary loading changed the new content' unless potter.verified? && potter_questions.size == 985 &&
  potter_questions.all? { |q| [q.fetch('prompt'), q.fetch('correct'), *q.fetch('wrong')].all? { |s| s.encoding == Encoding::UTF_8 && s.valid_encoding? } }
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
manifest = BinaryRulesLoad.metadata
raise 'Wrong runtime version' unless EltenGameRoom::GAME_ROOM_VERSION == manifest.fetch('version') &&
  EltenGameRoom::GAME_ROOM_BUILD_ID == manifest.fetch('build_id').to_i
sound = BinaryRulesLoad.read(File.join(BinaryRulesLoad::ROOT, 'Audio/quiz_wrong_answer.opus'))
raise 'Missing Opus sound' unless sound.start_with?('OggS') && sound.byteslice(0, 128).include?('OpusHead')
puts 'PASS binary Quiz status and release 245 in PL/EN/CS/ES/RU/fallback, controls and packaged sound'
