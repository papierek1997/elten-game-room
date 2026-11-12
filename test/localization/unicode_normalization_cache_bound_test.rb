require_relative '../../lib/game_content'
require_relative '../../lib/mania_pisania/text_library'
require_relative '../support/assertions'
require 'timeout'
include GameRoomTest::Assertions

class RejectedNormalizationImport
  attr_reader :writes
  def initialize; @writes = 0; end
  def read_json(_path, default:); Marshal.load(Marshal.dump(default)); end
  def write_json(*); @writes += 1; raise 'Rejected text reached persistence'; end
end

normalizer = UnicodeNormalize
caches = [normalizer::NF_HASH_C, normalizer::NF_HASH_D]
caches.each(&:clear)
program = RejectedNormalizationImport.new
library = GameRoomTyping::TextLibrary.new(program)
24.times do |index|
  text = 'a' + ("\u0301" * (8192 + index))
  assert(text.bytesize < GameRoomTyping::TextLibrary::MAX_BYTES)
  assert_raises(GameRoomTyping::UnsupportedCharacters) { library.import_text(text, title: 'Rejected combining text') }
end
GC.start
retained = caches.sum { |cache| cache.sum { |key, value| key.bytesize + value.bytesize } }
assert_equal(0, program.writes)
assert(retained < 16_384, "Rejected imports retained #{retained} normalization payload bytes")

# All four forms keep the identical table/algorithm result when a matched
# sequence is too large to cache. The oracle bypasses only the Hash itself.
reference = lambda do |text, form|
  case form
  when :nfc then text.gsub(normalizer::REGEXP_C) { |key| normalizer.nfc_one(key) }
  when :nfd then text.gsub(normalizer::REGEXP_D) { |key| normalizer.nfd_one(key) }
  when :nfkc then text.gsub(normalizer::REGEXP_K, normalizer::KOMPATIBLE_TABLE).
    gsub(normalizer::REGEXP_C) { |key| normalizer.nfc_one(key) }
  when :nfkd then text.gsub(normalizer::REGEXP_K, normalizer::KOMPATIBLE_TABLE).
    gsub(normalizer::REGEXP_D) { |key| normalizer.nfd_one(key) }
  end
end
samples = ["a\u0301", "\uAC01", "\u1100\u1161\u11A8", "\uFF21\u2460\uFB01",
  "\u{105D2}\u0307", "a" + "\u0301\u0315\u0328" * 200, "\uFB03" + "\u0301" * 200]
samples.each do |text|
  %i[nfc nfd nfkc nfkd].each do |form|
    expected = reference.call(text, form)
    original = text.dup
    assert_equal(expected, normalizer.normalize(text, form))
    assert_equal(expected == text, normalizer.normalized?(text, form))
    assert_equal(original, text, 'Normalization mutated caller input')
  end
end

# Small hot entries still cache and hit without replacing their value. Both
# decomposition and composition respect the count exactly, not limit + 1.
[[normalizer::NF_HASH_C, "a\u0301", :nfc], [normalizer::NF_HASH_D, "\u00E1", :nfd]].each do |cache, key, form|
  cache.clear
  normalizer.normalize(key, form)
  cached = cache.fetch(key)
  normalizer.normalize(key, form)
  assert(cache.fetch(key).equal?(cached), 'Normal hot entry was not reused')
  cache.clear
  normalizer::MAX_HASH_LENGTH.times { |index| cache["fixture:#{index}"] = 'x' }
  normalizer.normalize(key, form)
  assert_equal(normalizer::MAX_HASH_LENGTH, cache.length, 'Insertion exceeded the count bound')
  assert(cache.key?(key) && !cache.key?('fixture:0'), 'Count bound evicted the wrong edge')
end

# Admission measures both the key and its normalized result in bytes. In NFD
# a short precomposed source can expand; checking only input length is wrong.
caches.each(&:clear)
key = "\u1E69" * 40
assert(key.bytesize <= normalizer::MAX_CACHE_ENTRY_BYTES)
expected = normalizer.nfd_one(key)
assert(key.bytesize + expected.bytesize > normalizer::MAX_CACHE_ENTRY_BYTES)
assert_equal(expected, normalizer::NF_HASH_D[key])
assert(!normalizer::NF_HASH_D.key?(key), 'Expanded value exceeded the per-entry payload cap')

# Pause at the REAL Hash#length c_return, without replacing any algorithm or
# Hash method. Before serialization both cold misses observe limit-1. After
# serialization the second waits for admission, not for this tracing gate.
[[normalizer::NF_HASH_C, ["a\u0301", "o\u0301"], :nfc],
 [normalizer::NF_HASH_D, ["\u00E1", "\u00F3"], :nfd]].each do |cache, keys, form|
  cache.clear
  (normalizer::MAX_HASH_LENGTH - 1).times { |index| cache["fixture:#{index}"] = 'x' }
  arrived, release = Queue.new, Queue.new
  workers, seen = [], {}
  trace = TracePoint.new(:c_return) do |event|
    next unless event.method_id == :length && event.self.equal?(cache) &&
      Thread.current[:normalization_cache_probe] && !seen[Thread.current]
    seen[Thread.current] = true
    arrived << event.return_value
    release.pop
  end
  begin
    trace.enable
    workers << Thread.new { Thread.current[:normalization_cache_probe] = true; normalizer.normalize(keys[0], form) }
    assert_equal(normalizer::MAX_HASH_LENGTH - 1, Timeout.timeout(5) { arrived.pop })
    workers << Thread.new { Thread.current[:normalization_cache_probe] = true; normalizer.normalize(keys[1], form) }
    Timeout.timeout(5) { Thread.pass until !arrived.empty? || workers[1].status == 'sleep' }
    2.times { release << true }
    results = Timeout.timeout(5) { workers.map(&:value) }
    assert_equal(keys.map { |text| reference.call(text, form) }, results)
    assert_equal(normalizer::MAX_HASH_LENGTH, cache.length, 'Concurrent misses exceeded the count bound')
  ensure
    trace.disable
    2.times { release << true }
    workers.each { |worker| worker.join(5) }
  end
end
puts "PASS normalization cache: rejected imports retained #{retained} bytes; four forms unchanged, small hits preserved, exact count and key+value byte bounds"
