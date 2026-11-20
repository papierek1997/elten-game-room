require "open3"
require "rbconfig"
require 'prism'

def assert(value, message); raise message unless value; end
root = File.expand_path("../..", __dir__)
paths = Dir.glob('test/**/*.rb', base: root)
assert(!paths.empty?, 'No test sources were checked')
# This regression tests the actual parent cleanup methods, not reusable
# fixtures. Both subjects have guarded entry points; their definition-only
# import and direct execution are checked by local_table_import_boundary_test.
subjects = [
  ['test/tooling/owned_worker_cleanup_test.rb', '../tournaments/drafts_test'],
  ['test/tooling/owned_worker_cleanup_test.rb', '../tournaments/local_test_tables_test']
]
observed_subjects = []
imports = paths.flat_map do |relative|
  path = File.join(root, relative)
  found = []
  nodes = [Prism.parse_file(path).value]
  while (node = nodes.pop)
    nodes.concat(node.compact_child_nodes)
    next unless node.is_a?(Prism::CallNode) && %i[require_relative require load].include?(node.name)
    argument = node.arguments&.arguments&.first
    if argument.is_a?(Prism::StringNode) && argument.unescaped.match?(/_test(?:\.rb)?\z/)
      identity = [relative, argument.unescaped]
      if node.name == :require_relative && subjects.include?(identity)
        observed_subjects << identity
        next
      end
      found << "#{path}:#{node.location.start_line}"
    end
  end
  found
end
assert(observed_subjects.sort == subjects.sort, 'A cleanup subject exception is stale, missing or duplicated')
assert(imports.empty?, "A test still imports another scenario: #{imports.join(', ')}")
%w[audio_ball_point_audio axel_pong_doubles_lobby audio_tutorial_native table_lifecycle_controls_2 no_bot_table_control post_233_ping table_notice_presentation game_option_encoding score_announcements card_reshuffle translation_reference makao_positions].each do |name|
  helper = File.join(root, "test/support/#{name}.rb")
  output, status = Open3.capture2e(RbConfig.ruby, "-r", helper, "-e", 'puts "fixture loaded"')
  assert(status.success? && output.lines.last.to_s.strip == "fixture loaded", "#{name}: fixture failed: #{output}")
  assert(!output.match?(/^(?:PASS|FAIL|All |passed:|\[\d+\/)/), "#{name}: import ran another scenario: #{output}")
end
puts "PASS fixture boundaries: no unapproved scenario imports; audited definition-only cleanup subjects; native/point/lifecycle/ping/notification helpers load without scenarios"
