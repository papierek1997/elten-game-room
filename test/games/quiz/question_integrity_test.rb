# encoding: UTF-8
require 'json'
require_relative "../../../content/languages"
require_relative "../../../content/quiz_general_en"
require_relative "../../../content/quiz_pl_wikidata"
require_relative "../../../content/quiz_witcher_pl"

def assert(value, message); raise message unless value; end
root = File.expand_path("../../..", __dir__)
reference = JSON.parse(File.read(File.join(root, 'test/fixtures/quiz/questions.json'), encoding: 'UTF-8'))
expected_packs = reference.fetch('packs')
packs = expected_packs.to_h { |id, _| [id, GameRoomContent.registry.pack(id)] }
assert(packs.values.none?(&:verified?), 'Quiz registration should remain lazy')
data = packs.to_h do |id, pack|
  qs = pack.data.fetch('questions')
  indexed = qs.to_h { |q| [q.fetch('id'), q] }
  assert(qs.size == expected_packs.fetch(id).fetch('count') && pack.entry_count == qs.size, "Wrong count: #{id}")
  assert(indexed.size == qs.size, "Duplicate IDs: #{id}")
  assert(pack.version == expected_packs.fetch(id).fetch('version') && pack.verified?, "Version/checksum: #{id}")
  assert(pack.checksum == expected_packs.fetch(id).fetch('checksum'), "Unexpected checksum: #{id}")
  qs.each do |q|
    assert(q.fetch('prompt').valid_encoding? && !q.fetch('prompt').strip.empty?, 'Invalid prompt')
    options = [q.fetch('correct'), *q.fetch('wrong')]
    normalized = options.map { |s| UnicodeNormalize.normalize(s, :nfkc).strip.downcase }
    assert(normalized.size == 4 && normalized.uniq.size == 4 && normalized.none?(&:empty?), "Invalid choices: #{q['id']}")
  end
  [id, indexed]
end
reference.fetch('excluded_ids').each do |pack_id, ids|
  ids.each do |id|
    assert(!data.fetch(pack_id).key?(id), "Rejected question remains: #{id}")
  end
end
general = data.fetch('quiz.wikidata.pl')
expected_categories = ['Geografia', 'Historia', 'Kultura', 'Literatura', 'Nauka',
  'Przyroda', 'Religia', 'Sport', 'Język', 'Społeczeństwo', 'Życie codzienne']
assert(general.values.map { |q| q.fetch('category') }.uniq.sort == expected_categories.sort, 'Polish general categories differ from the reviewed set')
source_prefixes = {'PolQA' => 'polqa_', '1z10/MAUPQA' => '1z10_', 'Milionerzy/Polsat' => 'milionerzy_'}
assert(general.values.map { |q| q.fetch('source_dataset') }.uniq.sort == source_prefixes.keys.sort, 'Polish general source datasets are incomplete')
general.each do |id, question|
  prefix = source_prefixes.fetch(question.fetch('source_dataset'))
  assert(id.start_with?(prefix), "#{id}: source identity was regenerated or the retired data returned")
  assert(id.length.between?(1, 32) && !id.match?(/[,\r\n]/), "#{id}: question ID cannot travel in a Quiz event")
  assert(!question.fetch('source').strip.empty? && !question.fetch('source_license').strip.empty?, "#{id}: missing source attribution or rights")
  [question.fetch('prompt'), question.fetch('correct'), *question.fetch('wrong')].each do |text|
    assert(text.encoding == Encoding::UTF_8 && text.valid_encoding?, "#{id}: invalid Polish question encoding")
    assert(!text.match?(/[\r\n]/), "#{id}: multiline text breaks the numbered review export")
  end
end
# 1z10 source decisions 13594 and 16571: the original listed alternatives
# permit more than one answer; neither prompt may return with a new ID.
{
  '1z10_41736dcea8105d68' => 'Bostońska herbatka poprzedziła rewolucję francuską, amerykańską czy angielską?',
  '1z10_8e8ea94b029b7e6c' => 'Do stworzenia akwaforty używa się pędzla, stalowej igły czy dłuta?'
}.each do |id, prompt|
  assert(!general.key?(id) && general.values.none? { |q| q.fetch('prompt') == prompt }, "Ambiguous reviewed question returned: #{id}")
end
books = data.fetch('quiz.witcher.books.pl').values
books.each do |q|
  assert(q.fetch('id').length <= 32, 'Witcher question ID exceeds the event limit')
  assert(q.fetch('source').start_with?('Andrzej Sapkowski:'), 'Missing literary attribution')
  assert(!q.fetch('prompt').match?(/Netflix|CD Projekt|GWINT|ekranizacj/i), 'An adaptation question returned')
end
puts "Quiz question integrity: pinned content, excluded questions, sources and lazy packs: OK"
