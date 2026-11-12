require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'digest'
require 'json'
require 'base64'
require 'zlib'

repository = File.expand_path('../..', __dir__)
Dir.mktmpdir('typing-output-set-') do |root|
  FileUtils.mkdir_p([File.join(root, 'tools/support'), File.join(root, 'content')])
  %w[tools/build-typing-word-list.rb tools/support/output_set.rb].each do |path|
    FileUtils.cp(File.join(repository, path), File.join(root, path))
  end
  script = File.join(root, 'tools/build-typing-word-list.rb')
  source, sorted, runtime = %w[source.txt sorted.txt content/mania_pisania_words_en.rb].map { |path| File.join(root, path) }
  original = ['PREVIOUS COMPLETE EXPORT\n', 'PREVIOUS COMPLETE RUNTIME\n']
  [sorted, runtime].zip(original).each { |path, bytes| File.binwrite(path, bytes) }
  before = [sorted, runtime].map { |path| File.binread(path) }
  ["a\nb\n", "valid\n\xff\n".b].each do |bytes|
    File.binwrite(source, bytes)
    _output, error, status = Open3.capture3(RbConfig.ruby, script, 'en', source, sorted)
    raise 'Malformed source unexpectedly succeeded' if status.success? || error.empty?
    raise 'Invalid build replaced part of the previous output set' unless [sorted, runtime].map { |path| File.binread(path) } == before
  end

  File.binwrite(source, "dog\nżaba\ncat\ncat\nкот\n")
  fault = File.join(root, 'rename_fault.rb')
  File.binwrite(fault, <<~RUBY)
    module TypingOutputFault
      def rename(from, to)
        if to == #{runtime.dump} && File.basename(from).start_with?('.game-room-output-stage-')
          raise IOError, 'Injected second-output replacement failure'
        end
        super
      end
    end
    File.singleton_class.prepend(TypingOutputFault)
  RUBY
  _output, error, status = Open3.capture3(RbConfig.ruby, '-r', fault, script, 'en', source, sorted)
  raise 'Fault did not reach the second replacement' if status.success? || !error.include?('Injected second-output')
  raise 'A failed second replacement left a mixed output set' unless [sorted, runtime].map { |path| File.binread(path) } == before

  output, error, status = Open3.capture3(RbConfig.ruby, script, 'en', source, sorted)
  raise error unless status.success?
  report = JSON.parse(output)
  sorted_bytes = File.binread(sorted).force_encoding('UTF-8')
  expected = %w[cat dog żaba кот].sort
  raise 'Valid export changed normalization or Unicode' unless sorted_bytes == expected.join("\n") + "\n"
  namespace = Module.new
  namespace.module_eval(File.binread(runtime), runtime)
  data = namespace.const_get(:GameRoomTyping).const_get(:WordDataEN)
  pack = data::BLOCKS.map { |block| Zlib::Inflate.inflate(Base64.strict_decode64(block)).force_encoding('UTF-8') }.join
  raise 'Generated pack differs from its complete source' unless pack == sorted_bytes && data::COUNT == expected.size
  raise 'Output checksums do not match committed bytes' unless data::CHECKSUM == Digest::SHA256.hexdigest(pack) &&
    report['full_list_sha256'] == Digest::SHA256.hexdigest(sorted_bytes)
  raise 'Temporary stage/backup leaked' unless Dir.glob(File.join(root, '**/.game-room-output-*')).empty?
end
puts 'PASS typing generator complete-set validation, invalid UTF-8, second-replacement rollback, Unicode and checksums'
