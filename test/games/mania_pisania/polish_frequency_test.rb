# encoding: UTF-8
require_relative '../../support/game_option_form'
require_relative '../../../lib/mania_pisania/word_bank'

game = GameRoomGames::ManiaPisania.new
options = game.table_creation_options('variant'=>'words', 'word_language'=>'pl')
current = GameRoomTyping::WordBank.for_options(options)
samples = 200.times.map { |index| current.call(10, index) }
[{}, {'word_pack'=>'legacy'}, {'word_pack'=>'hunspell-pl-v1'}].each do |obsolete|
  normalized = game.normalize_options(options.merge(obsolete))
  assert(!normalized.key?('word_pack'), 'Obsolete Polish dictionary metadata survived normalization')
  bank = GameRoomTyping::WordBank.for_options(options.merge(obsolete))
  assert(samples == 200.times.map { |index| bank.call(10, index) }, 'An obsolete Polish dictionary is still selected')
end
assert(game.normalize_options(nil)['word_language']=='pl', 'Nil options no longer normalize')
assert(!game.normalize_options(word_language:'pl', word_pack:'hunspell-pl-v1').key?('word_pack'), 'Symbol metadata survived')
assert(!GameRoomTyping.const_defined?(:WordData, false), 'The removed supplied Polish dictionary was loaded')
words = GameRoomTyping::WordDataPL::BLOCKS.flat_map do |block|
  Zlib::Inflate.inflate(Base64.strict_decode64(block)).force_encoding('UTF-8').split("\n")
end
source_path = File.expand_path('../../../tools/data/typing-polish-words.txt', __dir__)
reviewed = File.readlines(source_path, encoding:'UTF-8', chomp:true).map { |word| word.delete_suffix("\r") }
assert(GameRoomTyping::WordDataPL::COUNT == 29_987, 'The final reviewed Polish word count changed')
assert(words == reviewed.sort, 'The runtime list differs from the final reviewed list')
manifest = JSON.parse(File.read(File.expand_path('../../../tools/data/typing-word-packs.json', __dir__)))
assert(Digest::SHA256.file(source_path).hexdigest == manifest.fetch('languages').fetch('pl').fetch('curated_source_sha256'),
  'Reviewed source checksum differs from the manifest')
assert(%w[dom domu domem domy kot kota koty ust].all? { |word| words.include?(word) }, 'Common inflections are missing')
assert((words & %w[spacjalny tys mln wys the]).empty?, 'Rare or excluded forms entered the common pool')
(3..12).each do |length|
  assert(current.word(123, length, length:length).length == length, 'A playable word length is unavailable')
end
guest = GameRoomTyping::WordBank.for_options(game.options_from_json(JSON.generate(options)))
assert(samples == 200.times.map { |index| guest.call(10, index) }, 'Players disagree on Polish word sequences')
puts 'PASS exact reviewed Polish list, all playable lengths, shared sequences and removal of both old dictionaries.'
