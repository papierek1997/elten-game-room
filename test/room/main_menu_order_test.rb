require_relative "../support/settings_widget"

expected = {
  "Create a new table" => :show_create_table,
  "Join a table" => :show_join_table,
  "Saved games" => :show_saved_games,
  "Leaderboards" => :show_leaderboards,
  "Statistics" => :show_statistics,
  "Settings" => :show_settings,
  "Game rules" => :show_rules_library,
  "README" => :show_readme,
  "What's new" => :show_changelog
}
assert(EltenGameRoom::MAIN_OPTIONS == expected.keys, "Main menu order differs from the agreed list")
app = EltenGameRoom.new
opened = []
expected.values.each { |method| app.define_singleton_method(method) { opened << method } }
app.define_singleton_method(:switch_to_invited_table) { raise "Menu entry unexpectedly accepted an invitation" }
expected.each_with_index do |(label, method), index|
  app.send(:open_main_option, index)
  assert(opened.last == method && opened.length == index + 1, "#{label} opens a different screen")
end
puts "PASS main menu: nine ordered entries, matching actions, no separate invitations entry"
