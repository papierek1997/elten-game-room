# encoding: UTF-8
# The reviewed list is authoritative. Never refill it from a frequency ranking.
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'

abort 'Usage: ruby tools/build-typing-polish-words.rb [SORTED_TXT]' if ARGV.length > 1
root = File.expand_path('..', __dir__)
manifest_path = File.join(__dir__, 'data/typing-word-packs.json')
manifest = JSON.parse(File.read(manifest_path, encoding: 'UTF-8'))
polish = manifest.fetch('languages').fetch('pl')
source = File.join(root, polish.fetch('curated_source'))
target = File.expand_path(ARGV.first || 'tmp/typing-polish-export.txt', root)
if File.exist?(target) && File.identical?(source, target)
  raise 'Keep the reviewed source unchanged; choose a separate export path'
end
bytes = File.binread(source)
text = bytes.dup.force_encoding(Encoding::UTF_8)
raise 'Invalid UTF-8 reviewed list' unless text.valid_encoding?
words = text.lines(chomp: true).map { |word| word.delete_suffix("\r") }
raise 'Empty reviewed list' if words.empty?
raise 'Invalid reviewed word; correct the source explicitly' unless words.all? { |word| word.match?(/\A[a-ząćęłńóśźż]{3,12}\z/) }
raise 'Duplicate reviewed word; correct the source explicitly' unless words.uniq.length == words.length
FileUtils.mkdir_p(File.dirname(target))
output, status = Open3.capture2(RbConfig.ruby, File.join(__dir__, 'build-typing-word-list.rb'), 'pl', source, target)
raise 'Word pack generation failed' unless status.success?
result = JSON.parse(output)
raise 'The reviewed list was filtered' unless result.fetch('playable_words') == words.length
polish.merge!('curated_source_sha256' => Digest::SHA256.hexdigest(bytes),
  'complete_count' => result.fetch('complete_forms'), 'complete_sha256' => result.fetch('full_list_sha256'),
  'runtime_count' => result.fetch('playable_words'), 'runtime_sha256' => result.fetch('checksum'))
File.binwrite(manifest_path, JSON.pretty_generate(manifest) + "\n")
puts output
