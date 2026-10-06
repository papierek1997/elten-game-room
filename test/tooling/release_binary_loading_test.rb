require_relative "../support/binary_rules_load"

%w[__app.rb games/mille_bornes.rb lib/game_sounds.rb content/quiz_general_ru.rb test/support/ui.rb tools/stage-release.rb].each do |relative|
  raise "Project source bypasses binary loading: #{relative}" unless BinaryRulesLoad.source_path?(File.join(BinaryRulesLoad::ROOT, relative))
end
%w[Workspace/runtime/library.rb snapshots/old/lib/library.rb trash/lib/library.rb tmp/library.rb].each do |relative|
  raise "Auxiliary dependency treated as packaged code: #{relative}" if BinaryRulesLoad.source_path?(File.join(BinaryRulesLoad::ROOT, relative))
end
raise "External dependency treated as packaged code" if BinaryRulesLoad.source_path?(File.expand_path("../external/lib/library.rb", BinaryRulesLoad::ROOT))

original_entries = BinaryRulesLoad.instance_variable_get(:@entries)
keys = %w[games/scrabble.rb lib/game_room_localization.rb locale/pl.mo]
entries = original_entries || keys.to_h do |key|
  path = key == "locale/pl.mo" ? "locale/PL.mo" : key
  [key, File.binread(File.join(BinaryRulesLoad::ROOT, path))]
end
raise "Development Ruby leaked into installer" if original_entries && entries.keys.any? { |path| path.start_with?("test/", "tools/") }
BinaryRulesLoad.instance_variable_set(:@entries, entries)
begin
  runtime = BinaryRulesLoad.localization_runtime(:pl)
  raise "App translator did not receive packaged MO bytes" unless runtime.language_data("pl") == entries.fetch("locale/pl.mo")
  keys.each do |key|
    content = entries.delete(key)
    begin
      begin
        if key == "locale/pl.mo"
          runtime.language_data("pl")
        else
          BinaryRulesLoad.read(File.join(BinaryRulesLoad::ROOT, key))
        end
        raise "Missing packaged runtime was silently read from disk: #{key}"
      rescue KeyError
      end
    ensure
      entries[key] = content
    end
  end
  path = File.join(BinaryRulesLoad::ROOT, "test/support/ui.rb")
  raise "Test harness cannot read its own support files" unless BinaryRulesLoad.read(path) == File.binread(path)
ensure
  BinaryRulesLoad.instance_variable_set(:@entries, original_entries)
end
puts "PASS release binary boundary: all game/data loading, external test harness, no production or catalog fallback"
