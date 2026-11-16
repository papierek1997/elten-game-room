require_relative "../../support/private_card_games"
require_relative "../../../games/hearts_support/hearts_table"

game = GameRoomGames::HeartsTable.new
h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob Carol Dan])
begin
  PrivateCardGamesTest.assert_private(h)
  65.times do
    replay = h.replay(h.users.first)
    actor = replay.current_player
    action = if replay.state[:phase] == :opening
      actor = h.users.find { |viewer| game.automatic_action(h.replay(viewer), viewer) }
      game.automatic_action(h.replay(actor), actor) if actor
    elsif actor
      game.legal_actions(h.replay(actor), actor).first
    end
    assert(action, "Missing action in #{replay.state[:phase]}, actor #{actor.inspect}, hands #{replay.state[:hands].transform_values(&:size)}, views #{h.users.map { |viewer| current = h.replay(viewer); [viewer, current.current_player, current.state[:passes], current.accepted_events.last&.fetch("action")] }.inspect}")
    PrivateCardGamesTest.submit(h, runners, actor, action)
    if action['kind'] == 'card' && replay.state[:phase] == :passing
      after = h.replay(actor)
      hand = game.surface_spec(after, actor).zones.first
      outgoing = after.state[:passes].fetch(actor, [])
      assert((hand.cards.map(&:id) & outgoing).empty?, 'A committed private card remained selectable')
      assert(hand.cards.map(&:id) == hand.cards.sort_by { |card| card.sort_keys['colour'] }.map(&:id),
        'The private hand lost suit sorting during passing')
      before = Marshal.dump(after)
      game.shortcut_feature_data(:hand, after, actor)
      assert(Marshal.dump(after) == before, 'The private hand reminder changed its audit')
    end
  end
  scores = h.users.map do |viewer|
    replay = h.replay(viewer)
    assert(replay.state[:phase] == :round_complete, "Wrong final phase: #{replay.state[:phase]}")
    replay.state[:scores]
  end
  assert(scores.uniq.one?, "Viewers disagree on scores")
  assert([26, 78].include?(scores.first.values.sum), "Invalid score")
  puts "PASS Hearts private passing and complete round"
ensure
  runners.each_value(&:close)
end
