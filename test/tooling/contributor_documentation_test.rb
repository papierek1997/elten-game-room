# Check maintained contributor routes, not the quality/facts of natural prose.
require 'uri'
require 'shellwords'
require_relative '../support/assertions'
require_relative '../support/suites'
include GameRoomTest::Assertions

ROOT = File.expand_path('../..', __dir__)
# Dated plans retain their historical paths and status; the index explicitly
# distinguishes them from maintained contracts. All current guides participate.
DOCUMENTS = (%w[AGENTS.md CONTRIBUTING.md .github/pull_request_template.md] +
  Dir.glob('docs/*.md', base: ROOT).reject do |path|
    File.basename(path).match?(/\A(?:AUDIT_PLAN_|FIXES_PLAN_|NEXT_FIXES_PLAN\.|DUCK_RACING_PLAN\.)/)
  end).sort.freeze

def outside_fences(text)
  fence = nil
  visible = text.lines.filter_map do |line|
    if (match = line.match(/^\s*(`{3,}|~{3,})/))
      if fence
        fence = nil if match[1][0] == fence[0] && match[1].length >= fence[1] && line.strip == match[1]
      else
        fence = [match[1][0], match[1].length]
      end
      next
    end
    line unless fence
  end.join
  assert(fence.nil?, 'Unclosed documentation code fence')
  visible
end

def heading_ids(text)
  seen = Hash.new(0)
  outside_fences(text).scan(/^\#{1,6}\s+(.+?)\s*#*$/).flatten.map do |title|
    slug = title.downcase.gsub(/[^\p{L}\p{M}\p{N}\s_-]/, '').gsub(/\s/, '-')
    count = seen[slug]
    seen[slug] += 1
    count.zero? ? slug : "#{slug}-#{count}"
  end
end

assert_equal("# Visible\n", outside_fences("# Visible\n~~~~\n```ruby\n# Hidden\n```\n~~~~\n"))
assert_raises(RuntimeError) { outside_fences("```ruby\n# Unclosed\n") }
paths = GameRoomTestSuites.paths.to_h { |path| [path, true] }
links = commands = snippets = 0
DOCUMENTS.each do |relative|
  file = File.join(ROOT, relative)
  text = File.read(file, encoding: 'UTF-8')
  assert(text.valid_encoding?, "Invalid UTF-8: #{relative}")
  outside_fences(text).scan(/\[[^\]\n]+\]\(([^\s)]+)\)/).flatten.each do |target|
    next if target.match?(/\A[a-z][a-z\d+.-]*:/i)
    path, fragment = target.split('#', 2).map { |part| URI::DEFAULT_PARSER.unescape(part) }
    absolute = path.empty? ? file : File.expand_path(path, File.dirname(file))
    assert(File.exist?(absolute), "#{relative}: missing link #{target}")
    if fragment && File.file?(absolute) && File.extname(absolute) == '.md'
      assert(heading_ids(File.read(absolute, encoding: 'UTF-8')).include?(fragment), "#{relative}: missing heading #{target}")
    end
    if absolute.end_with?('_test.rb')
      scenario = absolute.delete_prefix("#{ROOT}/")
      assert(paths[scenario], "#{relative}: referenced scenario is outside automatic CI discovery: #{target}")
    end
    links += 1
  end

  text.scan(/^```console\r?\n(.*?)^```/m).flatten.each do |block|
    block.lines.grep(/^ruby test\/run\.rb /).each do |line|
      arguments = Shellwords.split(line).drop(2)
      arguments.grep(/\Atest\//).each do |selection|
        assert(!Dir.glob(selection, base: ROOT).empty?, "#{relative}: nonexistent test selection #{selection}")
      end
      commands += 1
    end
  end
  text.scan(/^```ruby\r?\n(.*?)^```/m).flatten.each do |source|
    RubyVM::InstructionSequence.compile(source, file)
    snippets += 1
  end
end
assert(links.positive? && commands.positive? && snippets.positive?, 'Documentation check selected no links, commands or Ruby examples')
tool_rows = File.read(File.join(ROOT, 'docs/TOOLS.md'), encoding: 'UTF-8').lines.grep(/^\| `/)
tool_rows.each do |row|
  row.split('|')[1].scan(/`([^`]+)`/).flatten.each do |tool|
    assert(File.file?(File.join(ROOT, 'tools', tool)), "Tool index names a missing command: #{tool}")
  end
end
puts "PASS contributor documentation: #{links} local links/anchors, referenced CI scenarios, #{commands} runner commands and #{snippets} Ruby syntax examples; behavior/editorial review are separate"
