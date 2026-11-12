# Explicit native-tool check: requires a built exporter, not a stub or a
# network download hidden inside the ordinary Ruby test suite.
require 'tmpdir'
require 'open3'

raise ArgumentError, 'Usage: ruby test/tooling/check_typing_hunspell_export.rb path/to/typing-hunspell-export' unless ARGV.length == 1
exporter = File.expand_path(ARGV.fetch(0))
raise ArgumentError, 'Build the real pinned Hunspell exporter first' unless File.file?(exporter)

Dir.mktmpdir('power-games-hunspell-check-') do |directory|
  affix = File.join(directory, 'dictionary.aff')
  dictionary = File.join(directory, 'dictionary.dic')
  output = File.join(directory, 'output.txt')
  previous = "Previous valid complete export\n"
  File.binwrite(dictionary, "2\ncat/S\ndog\n")

  {
    'unsupported encoding' => "SET ISO8859-1\n",
    'unsupported complex prefixes' => "SET UTF-8\nCOMPLEXPREFIXES\n"
  }.each do |label, bytes|
    File.binwrite(affix, bytes)
    File.binwrite(output, previous)
    _stdout, stderr, status = Open3.capture3(exporter, affix, dictionary, output)
    raise "#{label}: expected input rejection, got #{status.exitstatus}: #{stderr}" if status.success? ||
      !stderr.include?('Exporter requires a UTF-8 dictionary without COMPLEXPREFIXES')
    raise "#{label}: the previous output was changed" unless File.binread(output) == previous
    absent = File.join(directory, 'not-created.txt')
    _stdout, stderr, status = Open3.capture3(exporter, affix, dictionary, absent)
    raise "#{label}: invalid input created an output" if status.success? || File.exist?(absent) ||
      !stderr.include?('Exporter requires a UTF-8 dictionary without COMPLEXPREFIXES')
  end

  File.binwrite(affix, "SET UTF-8\nSFX S Y 1\nSFX S 0 s .\n")
  _stdout, stderr, status = Open3.capture3(exporter, affix, dictionary, output)
  raise "Valid UTF-8 dictionary failed: #{stderr}" unless status.success?
  words = File.binread(output).force_encoding(Encoding::UTF_8)
  raise 'Valid output lost actual Hunspell suffix expansion' unless words.valid_encoding? && words.lines(chomp: true).sort == %w[cat cats dog]

  _stdout, stderr, status = Open3.capture3(exporter, affix, dictionary, directory)
  raise 'An unwritable output was not rejected' if status.success? || !stderr.include?('Cannot open word-list output')
  raise 'The output-open refusal altered the valid export' unless File.binread(output) == words
end
puts 'PASS real Hunspell exporter: unsupported input preserves existing/absent outputs, valid suffix expansion and output-open failure'
