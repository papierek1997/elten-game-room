# encoding: UTF-8
require 'json'
require 'digest'
require 'base64'
require 'zlib'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

manifest = JSON.parse(File.read(File.expand_path('../../../tools/data/typing-word-packs.json', __dir__)))
examples = {'pl'=>%w[kot kota koty dom domu domem domy], 'en'=>%w[play playing player players], 'cs'=>%w[kočka kočky kočkami],
  'es'=>%w[jugar jugando jugador jugadores], 'ru'=>%w[игра игры играми]}
%w[en pl cs es ru].each do |language|
  require_relative "../../../content/mania_pisania_words_#{language}"
  data = GameRoomTyping.const_get("WordData#{language.upcase}")
  checksum = Digest::SHA256.new
  count = 0
  previous = nil
  missing = examples.fetch(language).dup
  data::BLOCKS.each do |encoded|
    bytes = Zlib::Inflate.inflate(Base64.strict_decode64(encoded)).force_encoding('UTF-8')
    assert(bytes.valid_encoding? && bytes.bytesize <= 131_072, 'Word block exceeds runtime limits')
    checksum.update(bytes)
    bytes.each_line(chomp:true) do |word|
      assert(word.length.between?(3,12) && word.match?(/\A[\p{Latin}\p{Cyrillic}]+\z/), "Invalid runtime word #{word}")
      assert(!previous || previous < word, 'Word pack contains duplicates or unstable ordering')
      previous = word
      count += 1
      missing.delete(word)
    end
  end
  expected = manifest.fetch('languages').fetch(language)
  assert(count == data::COUNT && count == expected.fetch('runtime_count'), 'Incorrect word count')
  assert(checksum.hexdigest == data::CHECKSUM && checksum.hexdigest == expected.fetch('runtime_sha256'), 'Word content differs from its identity')
  assert(missing.empty?, "Missing inflections for #{language}: #{missing}")
end
puts 'PASS complete word-pack integrity, sorted unique Unicode words and representative inflections in five languages.'
