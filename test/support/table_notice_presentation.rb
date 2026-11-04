require_relative "table_watch_runtime"

Notice2.class_eval do
  def presentation(**options); FakePresentation.new(options); end
end
# Explicit fixture setup; never inherit settings/audio side effects from
# running the unrelated widget scenarios first.
EltenGameRoom.remember_settings(EltenGameRoom::DEFAULT_SETTINGS.merge("invitation_notifications" => "everyone", "invitation_sounds" => true))
EltenGameRoom.define_singleton_method(:sound_asset_path) { |name| %w[notice table_notice].include?(name) ? "C:/program-assets/#{name}.opus" : nil }
EltenGameRoom.define_singleton_method(:play_sound_from_asset) do |name, **options|
  (@table_notice_test_sounds ||= []) << [name, options]
end
