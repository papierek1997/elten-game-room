require "json"
require "open3"
require "rbconfig"

# Targeted coverage for Quiz Party and the shared parts changed by PR #3.
root = File.expand_path("..", __dir__)
names = %w[
  quiz_data_cleanup quiz_pack_builder quiz_party quiz_party_startup
  quiz_party_review_regressions quiz_party_translation witcher_medium_split witcher_content_audit game_content
  hidden_submissions_storage quiz_party_storage categories_storage
  game_option_form surface_framework packaged_rules_encoding categories
  tysiac room_interface game_rules_ui game_rules_translation game_messages_ui
  game_sounds observer_and_shortcut_regressions uno_straights
  native_live_sessions_store live_sessions_resilience live_sessions_multiplayer
  transport game_sync
  connection_recovery connection_recovery_ui synchronization_regressions
]
results = names.map do |name|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  stdout, stderr, status = Open3.capture3(RbConfig.ruby, "test/#{name}_test.rb", chdir: root)
  puts "#{status.success? ? 'PASS' : 'FAIL'} #{name}"
  warn stdout + stderr unless status.success?
  { name: name, exit_code: status.exitstatus,
    seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
    stdout: stdout, stderr: stderr }
end
if ARGV.first
  File.write(ARGV.first, JSON.pretty_generate(results) + "\n", encoding: "UTF-8")
end
abort "Quiz regression failures" unless results.all? { |r| r[:exit_code] == 0 }
puts "All #{results.length} targeted Quiz/integration tests passed. No live clients were used."
