require_relative "../../support/dealt_card_games"
require_relative "../../../lib/game_sounds"
include GameRoomTest::Assertions

table = GameRoomTest::DealtCardTable.new("bouillabaisse", count: 3, seed: 14)
seen = Hash.new(0)
6.times do |index|
  while table.state[:phase] == :playing
    before = table.replay
    actor = before.current_player
    action = table.game.legal_actions(before, actor).first
    assert_equal(:ok, table.act(actor, action))
    event, after = table.events.last, table.replay
    card, penalties, round = event.fetch("value"), before.state[:penalties], before.state[:round]
    expected = if [4, 5, 6].include?(round) && card == penalties["card"]
      "bouillabaisse_card"
    elsif [3, 5, 6].include?(round) && card[0] == penalties["rank"]
      "bouillabaisse_rank"
    elsif [2, 5, 6].include?(round) && card[1] == penalties["suit"]
      "draw2"
    end
    cues = Array(GameRoomSounds.event_cue(game: table.game, event: event, before_replay: before, after_replay: after,
      repository: table.repository, viewer: actor, include_result: false))
    assert_equal(["play", expected].compact, cues, "Wrong scoring cue in round #{round}, #{card}")
    seen[[round, expected]] += 1
  end
  table.deal if index < 5
end
%w[draw2 bouillabaisse_rank bouillabaisse_card].each do |cue|
  assert(seen.any? { |(_round, name), count| name == cue && count > 0 }, "Missing #{cue} fixture coverage")
  assert(GameRoomSounds::ASSET_NAMES.include?(cue), "Cue is not registered")
end
assert(seen[[1, nil]] > 0 && seen.keys.none? { |round, cue| round == 1 && cue }, "First round played irrelevant penalty cues")
game = table.game
state = table.replay.state.merge(round: 5, penalties: {"suit"=>"H", "rank"=>"Q", "card"=>"QH"})
before = GameRoomGames::Replay.new(state: state)
history = [GameRoomGames::HistoryEntry.new(kind: :play, value: "QH")]
cues = game.event_sound_cues(event: {"action"=>"play", "value"=>"QH"}, before_replay: before, after_replay: before,
  history: history, viewer: "Alice", random_variant: nil)
assert_equal(["play", "bouillabaisse_card"], cues, "Overlapping card played several conflicting pitches")
cues = game.event_sound_cues(event: {"action"=>"play", "value"=>"QH"}, before_replay: before, after_replay: before,
  history: [], viewer: "Alice", random_variant: nil)
assert_equal([], cues, "Rejected card made a scoring sound")
puts "PASS Bouillabaisse scoring sounds: accepted play, six rounds, active suit/figure/special card, overlap priority and rejected actions"
