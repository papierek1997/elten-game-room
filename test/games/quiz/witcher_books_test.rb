# encoding: UTF-8
require_relative "../../../lib/game_surfaces/specifications"
$LOAD_PATH.unshift(File.expand_path("../../..", __dir__))
def _(text); text; end
def p_(_context, text); text; end
require "json"
require_relative "../../../lib/game_random"
require_relative "../../../lib/game_bots"
require_relative "../../../lib/hidden_submissions"
require_relative "../../../lib/game_content"
require_relative "../../../content/languages"
require_relative "../../../content/quiz_witcher_pl"
require_relative "../../../games/quiz_party"

class WitcherBooksRepository
  def players_for(_session); %w[Alice Bob]; end
  def actor_of(event, _session = nil); event.fetch("actor"); end
  def event_id(event); event.fetch("id"); end
end

def assert(condition, message); raise message unless condition; end
pack = GameRoomContent.registry.pack("quiz.witcher.books.pl")
assert(pack && !pack.verified?, "Registration must not load the database")
assert(pack.title == "Wiedźmin — książki", "Wrong set title")
assert(pack.set_id == "quiz.witcher.books" && pack.version == 1, "New set must have its own identity")
%w[quiz.witcher.pl quiz.witcher.g.pl quiz.witcher.b.pl].each do |id|
  assert(GameRoomContent.registry.pack(id).nil?, "Retired Witcher set remains available: #{id}")
end
questions = pack.data.fetch("questions")
fixture = JSON.parse(File.read(File.expand_path("../../fixtures/quiz/questions.json", __dir__), encoding: "UTF-8"))
expected = fixture.fetch("packs").fetch(pack.id)
assert(questions.size == expected.fetch("count") && pack.checksum == expected.fetch("checksum"), "Wrong reviewed data")
assert(pack.verified? && questions.size == pack.entry_count, "Question count/checksum did not verify")
assert(questions.map { |q| q.fetch("id") }.uniq.size == questions.size, "Duplicate question IDs")
categories = ["Bohaterowie", "Fabuła", "Polityka i wojny", "Geografia", "Magia i wiedźmini", "Stworzenia i przyroda", "Życie i kultura"]
assert(questions.map { |q| q.fetch("category") }.uniq.sort == categories.sort, "Missing thematic category")
questions.each do |q|
  assert(q.fetch("id").match?(/\A[0-9a-f]{12}\z/), "Question ID is not safe for a quiz event")
  assert(q.fetch("source").start_with?("Andrzej Sapkowski:"), "Missing book attribution")
  assert([q.fetch("correct"), *q.fetch("wrong")].map(&:downcase).uniq.size == 4, "Repeated answer")
  {
    "Droga, z której się nie wraca" => /(?:Drog[aię]|Drodze), z której się nie wraca/,
    "Coś się kończy, coś się zaczyna" => /Coś się kończy, coś się zaczyna/
  }.each do |title, pattern|
    next unless q.fetch("source").start_with?("Andrzej Sapkowski: #{title}")
    assert(q.fetch("prompt").match?(pattern), "Extra story lacks an explicit title")
  end
end
assert(questions.none? { |q| q.fetch("prompt").match?(/Netflix|CD Projekt|GWINT|ekranizacj/i) }, "Adaptation material remains")

game = GameRoomGames::QuizParty.new
repository = WitcherBooksRepository.new
context = GameRoomGames::ActionContext.new(
  session_id: 244, table_id: 244,
  hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
  random_source: GameRoomRandom::SeededSource.new(244), now: 100
)
options = game.normalize_options("content_set_id" => pack.set_id, "content_language_id" => "pl-PL")
assert(game.selected_content_pack(options).equal?(pack), "Options select a different set")
assert(game.validation_error(options, player_count: 2).nil?, "New set cannot start a match")
assert(game.send(:pack_questions, options) == questions, "Runtime dropped questions")
assert(game.validation_error(options.merge("content_pack_checksum" => "0" * 64), player_count: 2), "Mismatched clients were accepted")
%w[quiz.witcher quiz.witcher.g quiz.witcher.b].each do |retired|
  stale = game.normalize_options("content_set_id" => retired, "content_language_id" => "pl-PL")
  assert(game.selected_content_pack(stale).nil?, "A retired set silently selected different questions")
  assert(game.validation_error(stale, player_count: 2), "A retired set did not produce an explanatory error")
  assert(game.send(:pack_questions, stale).empty?, "A retired set retained playable questions")
end
session = {"options" => JSON.generate(options)}
initial = game.replay(session, [], repository)
assert(initial.state[:phase] == :drawing, "Quiz did not start in drawing phase")
action = game.automatic_action(initial, "Alice", context: context)
status, plan = game.action_for(action, initial, "Alice", context: context)
assert(status == :ok && plan.events.size == 1, "Cannot draw categories")
event = plan.events.first
stored = [{"id" => 1, "actor" => "Alice", "action" => event.action, "value" => event.value, "created_at" => 100}]
replayed = game.replay(session, stored, repository)
assert(replayed.state[:phase] == :choosing, "Cannot replay the first category choice")
assert((replayed.state[:choices] - categories).empty?, "Category leaked from another set")
assert(replayed.state[:choices].size == 3, "Not enough categories for normal play")
puts "Witcher books: sole pack, lazy loading, source scope, options, checksum, start and replay: OK (#{questions.size} questions)"
