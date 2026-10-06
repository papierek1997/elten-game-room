if ARGV.first
  require_relative "../support/binary_rules_load"
else
  require_relative "../support/ui"
  require_relative "../../games/base"
  require_relative "../../lib/game_event_presenter"
end

def assert(value, message)
  raise message unless value
end

game = GameRoomGames::Base.new
announcements = []
game.define_singleton_method(:timer_announcements) { |_replay, _viewer, now:| announcements }
sounds, speech, resets = [], [], []
program = Object.new
program.define_singleton_method(:play_sound_from_asset) { |asset, **_options| sounds << asset; nil }
presenter = GameRoomEventPresenter.new(game: -> { game }, repository: -> {}, program: -> { program },
  viewer: -> { "Alice" }, client: -> {}, surface_state: -> {}, clock: -> { 10 }, covered: -> { false },
  speech: ->(text) { speech << text }, trace: ->(*) {}, history_changed: ->(*) {}, session_changed: -> { resets << true })

presenter.prepare_presentation_session({"id" => 90})
announcements.replace([["text", "Ten seconds remain."], ["sound", "", "buzzer2"],
  ["both", "Five seconds remain.", "ding"], ["", "No key", "buzzer"], ["empty", "", ""]])
2.times { presenter.announce_due_timers(nil, now: 10) }
assert(speech == ["Ten seconds remain.", "Five seconds remain."], "Text timers must retain speech without duplicates")
assert(sounds == ["buzzer2", "ding"], "Sound-only and combined timers must play once through the program audio path")
assert(!presenter.spoken_timer_announcements.key?("empty"), "Empty announcements must not consume a future cue")

announcements.replace([["empty", "Ready", "ding"]])
presenter.announce_due_timers(nil, now: 11)
assert(speech.last == "Ready" && sounds.count("ding") == 2, "A formerly empty timer must still be deliverable")
assert(presenter.prepare_presentation_session({"id" => 7}, background: true), "Random smaller rematch IDs must be accepted")
announcements.replace([["sound", nil, "buzzer2"]])
presenter.announce_due_timers(nil, now: 12)
assert(sounds.count("buzzer2") == 2 && resets.length == 1, "New matches must reset timer deduplication once")
assert(!presenter.prepare_presentation_session({"id" => 90}), "Retired foreground matches must not reset background timer state")
presenter.announce_due_timers(nil, now: 13)
assert(sounds.count("buzzer2") == 2, "Returning from an old view must not repeat a timer sound")
puts "PASS optional timer sounds: legacy speech, sound-only, combined, deduplication, empty cues and random-ID rematches"
