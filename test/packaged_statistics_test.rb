require_relative "support/binary_rules_load"

raise "Statistics code is missing from binary package" unless defined?(GameRoomStatistics::Store) && defined?(GameRoomStatisticsScreen)
raise "Current-room code is missing from binary package" unless defined?(GameRoomPresence::Store) && defined?(GameRoomPresenceScreen)
raise "Missing binary collector" unless defined?(GameRoomPresence::Collector)
raise "Wrong Polish statistics title" unless RULES_CATALOG.fetch("Statistics") == "Statystyki"
raise "Wrong Polish current-room title" unless RULES_CATALOG.fetch("Current room activity") == "Obecnie w pokojach"
options = EltenGameRoom::MAIN_OPTIONS
raise "Statistics is not below rankings in package" unless options.index("Statystyki") == options.index(RULES_CATALOG.fetch("Leaderboards")) + 1

schemas = GameRoomStatistics::Schema::TABLES.merge(GameRoomPresence::Schema::TABLES)
schemas.each do |name, schema|
  raise "Missing packaged schema: #{name}" unless EltenGameRoom::SERVER_TABLES[name] == schema
  next unless schema["visibility"] == "public"
  hidden = %w[__insertion_user __last_update_user __insertion_time __last_update_time]
  raise "Unsafe public metadata policy: #{name}" unless schema["filter_for"] == "everyone" && schema["filtered_columns"].sort == hidden.sort
end
raise "Packaged presence exposes cross-room bundles" if schemas.fetch("room_presence").fetch("columns").key?("rooms_json")

original_mode = $developer_mode
begin
  $developer_mode = false
  raise "Normal-mode analytics are disabled" unless EltenGameRoom.analytics_enabled?
  $developer_mode = true
  raise "Developer analytics are enabled" if EltenGameRoom.analytics_enabled?
  raise "Developer statistics were initialized" unless EltenGameRoom.statistics_service.nil?
  raise "Developer presence was initialized" unless EltenGameRoom.room_presence_collector.nil?
ensure
  $developer_mode = original_mode
end

periods = GameRoomStatistics::Periods.options(today: Date.new(2027, 1, 2), years: [2026, 2027])
raise "Packaged statistics periods are incomplete" unless periods.map(&:key) == %w[today last_7 last_30 last_365 year_2027 year_2026 all_time]
raise "Packaged room identity generator is invalid" unless GameRoomPresence::Identity.valid?(GameRoomPresence::Identity.create)

required = %w[lib/game_statistics_store.rb lib/game_statistics_service.rb lib/game_statistics_queue.rb
  lib/game_statistics_identity.rb lib/game_statistics_periods.rb lib/game_statistics_screen.rb
  lib/game_room_presence_store.rb lib/game_room_presence_collector.rb lib/game_room_presence_identity.rb
  lib/game_room_presence_screen.rb]
required.each do |relative|
  path = File.join(BinaryRulesLoad::ROOT, relative)
  raise "Production dependency did not load from binary: #{relative}" unless BinaryRulesLoad.instance_variable_get(:@loaded)[path]
  raise "Empty packaged source: #{relative}" if BinaryRulesLoad.read(path).empty?
end
puts "PASS binary statistics/presence: schemas, privacy, Polish labels, periods, dev opt-out and #{required.length} production modules"
