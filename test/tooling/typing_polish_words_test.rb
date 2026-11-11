# encoding: UTF-8
require 'base64'
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'zlib'
require_relative '../support/assertions'
include GameRoomTest::Assertions

root = File.expand_path('../..', __dir__)
Dir.mktmpdir('reviewed-polish-') do |fixture|
  FileUtils.mkdir_p(File.join(fixture, 'tools/data'))
  FileUtils.mkdir_p(File.join(fixture, 'content'))
  %w[build-typing-word-list.rb build-typing-polish-words.rb].each do |name|
    FileUtils.cp(File.join(root, 'tools', name), File.join(fixture, 'tools', name))
  end
  manifest_path = File.join(fixture, 'tools/data/typing-word-packs.json')
  File.binwrite(manifest_path, JSON.generate('languages'=>{'pl'=>{'curated_source'=>'tools/data/typing-polish-words.txt'}}))
  source_path = File.join(fixture, 'tools/data/typing-polish-words.txt')
  source = "koty\r\nkot\r\ndom\r\nzażółć\r\n"
  File.binwrite(source_path, source)
  command = [RbConfig.ruby, File.join(fixture, 'tools/build-typing-polish-words.rb')]
  output, status = Open3.capture2e(*command, chdir:fixture)
  assert(status.success?, output)
  assert(File.binread(source_path) == source.b, 'Generation edited the reviewed file')
  pack_path = File.join(fixture, 'content/mania_pisania_words_pl.rb')
  data = Module.new.module_eval(File.read(pack_path, encoding:'UTF-8') + "\nGameRoomTyping::WordDataPL")
  words = data::BLOCKS.flat_map { |block| Zlib::Inflate.inflate(Base64.strict_decode64(block)).force_encoding('UTF-8').split("\n") }
  assert(words == %w[dom kot koty zażółć], 'Generation changed the set of reviewed words')
  expected_pack, expected_manifest = File.binread(pack_path), File.binread(manifest_path)
  output, status = Open3.capture2e(*command, source_path, chdir:fixture)
  assert(!status.success? && output.include?('Keep the reviewed source unchanged'), 'Source overwrite was allowed')
  ["kot\nkot\n", "kot\nnot-a-word\n", "kot\n\n", "\xff\n".b].each do |invalid|
    File.binwrite(source_path, invalid)
    output, status = Open3.capture2e(*command, chdir:fixture)
    assert(!status.success?, "Invalid list was silently accepted: #{output}")
    assert(File.binread(source_path) == invalid.b, 'Validation modified the reviewed source')
    assert(File.binread(pack_path) == expected_pack && File.binread(manifest_path) == expected_manifest,
      'Invalid input partially replaced the last valid pack or manifest')
  end
end
puts 'PASS reviewed Polish generation preserves the exact source and word set, and rejects invalid input without replacing valid output.'
