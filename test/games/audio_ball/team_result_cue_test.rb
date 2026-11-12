require_relative '../../support/assertions'
require_relative '../../../games/audio_ball'
require_relative '../../../lib/game_simulation'
require_relative '../../../lib/game_sounds'
include GameRoomTest::Assertions

# A complete accepted match and the shared cue selection, with no audio device,
# realtime client, native form or hand-written terminal replay state.
def completed_audio_ball_match(players:, seats: nil, winning_side:, sets: 1)
  game = GameRoomGames::AudioBall.new
  options = game.normalize_options('team_size' => seats ? 2 : 0, 'sets_to_win' => sets)
  options = game.with_team_assignment(options, players: players, seats: seats) if seats
  repository = GameRoomSimulation::Repository.new(players)
  owner = players.first
  session = {'__id' => 1, '__players' => players, 'player_one' => owner,
    '__insertion_user' => owner, 'options' => JSON.generate(options)}
  events = []
  replay = game.replay(session, events, repository)
  random = GameRoomRandom::SeededSource.new(17)
  start_context = GameRoomGames::ActionContext.new(table_owner: owner, now: 0,
    random_source: random, local_data: {})
  start = game.automatic_action(replay, owner, context: start_context)
  status, plan = game.action_for(start, replay, owner, context: start_context)
  assert_equal(:ok, status, 'The normal start plan must be legal')
  command = plan.events.fetch(0)
  events << {'__id' => 1, '__insertion_user' => owner, 'actor' => owner,
    'action' => command.action, 'value' => command.value, 'created_at' => 0}
  replay = game.replay(session, events, repository)
  assert_equal(events, replay.accepted_events)
  assert_equal(0.0, game.bot_reward(replay, players.first), 'An unfinished match has no result reward')

  before_final = nil
  (sets * GameRoomGames::AudioBall::POINTS_TO_WIN).times do |rally|
    point = "#{rally}:#{winning_side}"
    context = GameRoomGames::ActionContext.new(table_owner: owner, now: (rally + 1) * 10,
      local_data: {'audio_ball_point' => point})
    selection = game.automatic_action(replay, owner, context: context)
    status, plan = game.action_for(selection, replay, owner, context: context)
    assert_equal(:ok, status, 'Every point must pass the real agreed-point action path')
    assert_equal(1, plan.events.length)
    command = plan.events.fetch(0)
    event = {'__id' => events.length + 1, '__insertion_user' => owner, 'actor' => owner,
      'action' => command.action, 'value' => command.value, 'created_at' => (rally + 1) * 10}
    before_final = replay
    events << event
    replay = game.replay(session, events, repository)
    assert_equal(events, replay.accepted_events, 'A rejected point cannot stand in for a completed game')
  end
  assert(!before_final.finished? && replay.finished?, 'The actual final accepted point must finish the match')
  [game, repository, session, events, before_final, replay]
end

cases = 0
[[0, 1, 0, 1], [0, 0, 1, 1], [1, 0, 1, 0], nil].each do |seats|
  players = seats ? %w[Alice Bob Carol Dave] : %w[Alice Bob]
  [0, 1].each do |winning_side|
    [1, 2].each do |sets|
      game, repository, session, events, before, after = completed_audio_ball_match(
        players: players, seats: seats, winning_side: winning_side, sets: sets)
      assert_equal(seats ? "team:#{winning_side}" : players[winning_side], after.winner)
      retained = Marshal.dump([session, events, before, after])
      players.each_with_index do |player, seat|
        won = (seats ? seats[seat] : seat) == winning_side
        expected = won ? 'win_party' : 'lose_party'
        [player, player.swapcase].each do |viewer|
          cues = GameRoomSounds.event_cue(game: game, event: events.last,
            before_replay: before, after_replay: after, repository: repository, viewer: viewer)
          assert_equal([expected], Array(cues), 'The shared final event must select exactly the correct result cue')
          assert_equal(won ? 1.0 : -1.0, game.bot_reward(after, viewer),
            "The completed result disagrees with the player's team: #{seats.inspect} #{viewer}")
          assert_equal(nil, GameRoomSounds.result_cue(game, nil, after, viewer), 'Cold reconstruction must be silent')
          assert_equal(nil, GameRoomSounds.result_cue(game, after, after, viewer), 'A refresh must not repeat the result cue')
        end
      end
      assert_equal(nil, GameRoomSounds.result_cue(game, before, after, 'Watcher'), 'An observer has no personal result cue')
      assert_equal(retained, Marshal.dump([session, events, before, after]), 'Result presentation mutated the accepted match')
      cases += 1
    end
  end
end
puts "PASS Audio Ball result cues: #{cases} complete legal singles/doubles matches, both winners, seat orders, sets, case, observer and replay silence"
