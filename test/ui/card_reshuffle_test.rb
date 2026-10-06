if ARGV.delete("--binary")
  require_relative "../support/binary_rules_load"
  BinaryRulesLoad.load(File.expand_path(__FILE__))
  exit
end
require_relative '../support/card_reshuffle'

types = [GameRoomGames::Uno, GameRoomGames::Makao, GameRoomGames::NinetyNine,
  GameRoomGames::Rummy, GameRoomGames::Poker]
types.each do |type|
  ["Alice", "bot:1:1"].each do |actor|
    game, repo, session, state, selection = reshuffle_fixture(type, actor)
    before = game.replay(session, [], repo)
    events = []
    after = append_action(game, session, repo, events, before, actor, selection, context_for)
    assert(after.accepted_events == events, "#{game.id}: action not accepted")
    entries = after.history.select { |entry| entry.kind == :reshuffle }
    assert(entries.length == 1, "#{game.id}: expected one reshuffle announcement, got #{entries.length}")
    assert(entries.first.text == "The deck was reshuffled.", "#{game.id}: announcement text")
    assert(entries.first.text.encoding == Encoding::UTF_8, "#{game.id}: binary announcement")
    assert(entries.first.event_id == repo.event_id(events.last), "#{game.id}: wrong event ID")
    assert(game.replay(session, events, repo).history == after.history, "#{game.id}: unstable replay history")
    assert(game.replay(session, events, repo).state == after.state, "#{game.id}: unstable shuffle")
    game.define_singleton_method(:record_deck_reshuffle) { |*_args| }
    without_message = game.replay(session, events, repo)
    game.singleton_class.send(:remove_method, :record_deck_reshuffle)
    assert(without_message.state == after.state && without_message.accepted_events == after.accepted_events,
      "#{game.id}: announcement changed the rules or shuffled cards")
    assert(without_message.history == after.history.reject { |entry| entry.kind == :reshuffle },
      "#{game.id}: announcement changed existing messages")
    event = events.last
    [actor, "Bob", "Observer"].each do |viewer|
      sounds = Array(GameRoomSounds.event_cue(game: game, event: event, before_replay: before,
        after_replay: after, repository: repo, viewer: viewer))
      assert(sounds.count("card-shuffle") == 1 && sounds.include?("draw"), "#{game.id}: reshuffle/draw layering")
      assert(!sounds.include?("shuffle"), "#{game.id}: new deal sound used for recycling")
      assert(Array(game.describe_event(event, repo, after, viewer)).include?(entries.first.text), "#{game.id}: missing speech")

      Session.name = viewer
      played = []
      $spoken_messages.clear
      program = Object.new
      program.define_singleton_method(:play_sound_from_asset) do |name, volume:|
        raise "Unexpected reshuffle volume: #{volume}" unless volume == 1.0
        played << name
        nil
      end
      screen = GameScreen.new(program: program, repository: repo, game: game, session: session,
        table: {}, table_owner: actor, room_snapshot_provider: nil, synchronizer: nil)
      screen.send(:process_new_events, before)
      screen.send(:process_new_events, after)
      assert(played.count("card-shuffle") == 1, "#{game.id}: live sound missing/duplicated")
      assert($spoken_messages.count(entries.first.text) == 1, "#{game.id}: live speech missing/duplicated")
      screen.send(:process_new_events, game.replay(session, events, repo))
      bad = event.merge("id" => 99, "actor" => "Stranger")
      rejected = game.replay(session, events + [bad], repo)
      assert(rejected.accepted_events == events, "#{game.id}: invalid actor accepted")
      screen.send(:process_new_events, rejected)
      reopened = GameScreen.new(program: program, repository: repo, game: game, session: session,
        table: {}, table_owner: actor, room_snapshot_provider: nil, synchronizer: nil)
      reopened.send(:process_new_events, after)
      assert(played.count("card-shuffle") == 1 && $spoken_messages.count(entries.first.text) == 1,
        "#{game.id}: refresh/rejection/reopening replayed reshuffle")
    end

    # Ordinary draws/exchanges with enough stock must not announce a shuffle.
    pile = game.id == "rummy" ? :stock : game.id == "poker" ? :deck : :draw_pile
    discards = game.id == "poker" ? :draw_discards : :discard
    available = state[discards].shift(8)
    state[pile].concat(available)
    ordinary = append_action(game, session, repo, [], game.replay(session, [], repo), actor, selection, context_for)
    assert(ordinary.history.none? { |entry| entry.kind == :reshuffle }, "#{game.id}: ordinary draw announces shuffle")
  end
end

# An exhausted stock with nothing that can be recycled is not a shuffle.
types.each do |type|
  game, repo, session, state, selection = reshuffle_fixture(type, "Alice")
  pile = game.id == "rummy" ? :stock : game.id == "poker" ? :deck : :draw_pile
  discards = game.id == "poker" ? :draw_discards : :discard
  state[pile].clear
  state[discards] = %w[ninety_nine poker].include?(game.id) ? [] : state[discards].last(1)
  before = game.replay(session, [], repo)
  status, plan = game.action_for(selection, before, "Alice", context: context_for)
  next unless status == :ok
  events = plan.events.each_with_index.map { |command, i| { "id" => i + 1, "actor" => "Alice", "action" => command.action, "value" => command.value } }
  after = game.replay(session, events, repo)
  assert(after.history.none? { |entry| entry.kind == :reshuffle }, "#{game.id}: empty pile falsely announced shuffle")
end

asset = "card-shuffle"
manifest = JSON.parse(File.read(File.expand_path("../../manifest.json", __dir__)))
embedded = JSON.parse(File.read(File.expand_path("../../__app.rb", __dir__)).split("=begin Elten3AppInfo", 2).last.split("=end Elten3AppInfo", 2).first)
assert(manifest == embedded, "source manifests disagree")
assert(manifest.dig("required_assets", "sounds").include?(asset) && GameRoomSounds::ASSET_NAMES.include?(asset), "unregistered reshuffle asset")
path = File.expand_path("../../Audio/#{asset}.opus", __dir__)
assert(File.binread(path, 4) == "OggS", "not an Ogg sound")
assert(Digest::SHA256.file(path).hexdigest == "50c1f9d26f6b6ff930aede6823a8ea16fb28f913aa5666a8ec38e13e87afce41", "reshuffle sound differs from the validated Opus conversion")
levels = { "sound_volumes" => { "all" => 50, "game" => 40 } }
played = []
program = Object.new
program.define_singleton_method(:game_room_sound_volume) { |name| GameRoomPreferences.sound_volume(levels, name) }
program.define_singleton_method(:play_sound_from_asset) { |name, volume:| played << [name, volume] }
GameRoomSounds.play_all(program, [asset, "draw"])
assert(played == [[asset, 0.2], ["draw", 0.2]], "reshuffle ignores game/master volume or layering")
levels["sound_volumes"]["game"] = 0
GameRoomSounds.play(program, asset)
assert(played.length == 2, "reshuffle ignores mute")
puts "PASS card reshuffle: five games, humans/bots/observers, history/speech/sound, replay silence, ordinary/new/empty decks, unchanged rules, assets and volume"
