# encoding: UTF-8
require_relative '../../../lib/game_surfaces/specifications'
$LOAD_PATH.unshift(File.expand_path('../../..', __dir__))
def _(text); text; end
def p_(_context, text); text; end
require 'json'
require_relative '../../../lib/game_random'
require_relative '../../../lib/game_bots'
require_relative '../../../lib/hidden_submissions'
require_relative '../../../content/languages'
require_relative '../../../content/quiz_harry_potter_pl'
require_relative '../../../games/quiz_party'
require_relative '../../../tools/support/release_files'

def assert(value, message); raise message unless value; end
class PotterBooksRepository
  def players_for(_session); %w[Alice Bob]; end
  def actor_of(event, _session = nil); event.fetch('actor'); end
  def event_id(event); event.fetch('id'); end
end

pack = GameRoomContent.registry.pack('quiz.harry_potter.books.pl')
assert(pack && !pack.verified?, 'Registration must not read the new question database')
assert(pack.set_id == 'quiz.harry_potter.books' && pack.language_id == 'pl-PL', 'Wrong set/language identity')
assert(pack.title == 'Harry Potter' && pack.author.include?('LordKiller'), 'Missing readable title or contributor credit')
reference = JSON.parse(File.read(File.expand_path('../../fixtures/quiz/questions.json', __dir__), encoding:'UTF-8'))
expected = reference.fetch('packs').fetch(pack.id)
questions = pack.data.fetch('questions')
assert(pack.verified? && questions.length == 985 && pack.entry_count == questions.length, 'Wrong verified question count')
assert(pack.version == expected.fetch('version') && pack.checksum == expected.fetch('checksum'), 'Reviewed data changed without updating its fixture')
assert(questions.map { |q| q.fetch('id') }.uniq.length == questions.length, 'Repeated question ID')
normalized = questions.map { |q| UnicodeNormalize.normalize(q.fetch('prompt'), :nfkc).downcase }
assert(normalized.uniq.length == normalized.length, 'Repeated question prompt')
categories = ['Bohaterowie', 'Eliksiry', 'Zaklęcia', 'Magiczne stworzenia', 'Magiczne przedmioty', 'Hogwart i inne miejsca', 'Quidditch', 'Fabuła']
assert(questions.map { |q| q.fetch('category') }.uniq.sort == categories.sort, 'Missing or renamed category')
questions.each do |q|
  assert(q.fetch('id').match?(/\Acommunity_hp_lk_\d{4}\z/) && q.fetch('id').length <= 32, 'ID cannot travel in a quiz event')
  texts = [q.fetch('prompt'), q.fetch('correct'), *q.fetch('wrong')]
  assert(texts.length == 5 && texts.all? { |s| s.encoding == Encoding::UTF_8 && s.valid_encoding? && !s.strip.empty? && !s.match?(/[\r\n]/) }, 'Invalid display text')
  assert(texts.drop(1).map { |s| UnicodeNormalize.normalize(s, :nfkc).downcase }.uniq.length == 4, 'Repeated answers')
  assert(q.fetch('source').start_with?('J.K. Rowling:'), 'Missing literary attribution')
  assert(q.fetch('author').include?('LordKiller') && q.fetch('source_license').include?('QUIZ_HARRY_POTTER_PL_SOURCES.md'), 'Lost contributor or rights notice')
  assert(q['review_required'] == false, 'Unreviewed question imported')
end
by_position = questions.to_h { |q| [q.fetch('id').split('_').last.to_i, q] }
[97,438,559,836,839,954,955,982].each { |n| assert(!by_position.key?(n), "Excluded item returned: #{n}") }
{
  7=>'Bilius', 11=>'Meropa Gaunt', 70=>'Bathilda Bagshot',
  215=>'Brazylia', 439=>'Siedemnaście', 440=>'Dwadzieścia dziewięć',
  505=>'Sto czterdzieści dwa', 935=>'Od 382 roku przed naszą erą'
}.each do |position, correct|
  assert(by_position.fetch(position).fetch('correct') == correct, "Incorrect reviewed detail: #{position}")
end
assert(by_position.fetch(604).fetch('prompt').include?('Trelawney'), 'Ambiguous Divination/Muggle Studies question returned')
assert(by_position.fetch(764).fetch('prompt').include?('po tym'), 'Bird attack moved back to the kiss itself')
assert(!by_position.fetch(574).fetch('wrong').include?('Wizyta Knota'), 'A supporting cause returned as a false answer')
assert(GameRoomReleaseFiles.allowed?('content/quiz_harry_potter_pl.rb') &&
  GameRoomReleaseFiles.allowed?('content/quiz_harry_potter_pl_data.rb') &&
  GameRoomReleaseFiles.allowed?('content/QUIZ_HARRY_POTTER_PL_SOURCES.md'), 'New content or rights notice will be missing from a future release')
assert(!GameRoomReleaseFiles.allowed?('tmp/quiz-review-20261031/potter/books/1.txt'), 'Private novel entered the release allowlist')

game = GameRoomGames::QuizParty.new
options = game.normalize_options('content_set_id'=>pack.set_id, 'content_language_id'=>'pl-PL')
assert(game.selected_content_pack(options).equal?(pack), 'Wrong set selected')
assert(game.validation_error(options, player_count:2).nil?, 'The new set cannot start')
assert(game.send(:pack_questions, options) == questions, 'Runtime discarded reviewed questions')
assert(game.validation_error(options.merge('content_pack_checksum'=>'0'*64), player_count:2), 'Different question content was accepted')
repository = PotterBooksRepository.new
context = GameRoomGames::ActionContext.new(
  session_id:7339, table_id:7339, now:100,
  hidden_submissions:HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
  random_source:GameRoomRandom::SeededSource.new(7339)
)
session = {'options'=>JSON.generate(options)}
events = []
replay = game.replay(session, events, repository)
append = lambda do |plan|
  plan.events.each do |event|
    assert(event.value.bytesize <= 64, 'A new category or question exceeds the action value limit')
    events << {'id'=>events.length+1, 'actor'=>'Alice', 'action'=>event.action, 'value'=>event.value, 'created_at'=>100}
  end
  game.replay(session, events, repository)
end
action = game.automatic_action(replay, 'Alice', context:context)
status, plan = game.action_for(action, replay, 'Alice', context:context)
assert(status == :ok, 'Cannot draw categories')
replay = append.call(plan)
surface = game.surface_spec(replay, 'Alice')
assert(surface.options.length == 3 && surface.options.all? { |o| categories.include?(o.id) && o.label == o.id }, 'Wrong category list')
action = GameSurfaces::Action.new(kind:'question', name:'submit', payload:{'question_id'=>surface.id, 'answer'=>surface.options.first.id})
status, plan = game.action_for(action, replay, 'Alice', context:context)
assert(status == :ok, 'Cannot choose a category')
replay = append.call(plan)
action = game.automatic_action(replay, 'Alice', context:context)
status, plan = game.action_for(action, replay, 'Alice', context:context)
assert(status == :ok, 'Cannot draw a question')
replay = append.call(plan)
assert(replay.state[:phase] == :answering, 'Question did not open')
surface = game.surface_spec(replay, 'Alice')
assert(surface.options.length == 4 && surface.options.map(&:label) == game.surface_spec(replay, 'Bob').options.map(&:label), 'Clients show different answer lists')
positions = questions.first(80).map do |question|
  state = replay.state.merge(question_id:question.fetch('id'))
  choices = game.send(:shuffled_options, state)
  assert(choices.sort == [question['correct'], *question['wrong']].sort, 'Shuffling changed an answer')
  choices.index(question.fetch('correct'))
end
assert(positions.uniq.size > 1, 'The correct answer stays at one fixed position')
puts 'Harry Potter: reviewed content, exclusions, provenance, lazy loading, native quiz flow and shuffled answers: OK (985 questions)'
