require_relative "../../lib/game_simulation"
require_relative "../../lib/presentation_replay"
require_relative "../../lib/game_sounds"
require_relative "../../lib/game_repository"
require_relative "../../games/uno"
require_relative "../../games/monopoly"
require_relative "../../games/spades"
require_relative "../../games/tic_tac_toe"
require_relative "../../games/four_in_a_row"
require_relative "../../games/farkle"

def _(text); text; end
def n_(one, many, count); count == 1 ? one : many; end
def assert(value, message); raise message unless value; end

def transition_signature(game, repository, event, before, after, viewer)
  [before, after, game.describe_event_for_display(event, repository, after, viewer),
    game.turn_transition_history_entry(before, after, event_id: repository.event_id(event)),
    GameRoomSounds.event_cue(game: game, event: event, before_replay: before,
      after_replay: after, repository: repository, viewer: viewer)]
end

comparisons = 0
[GameRoomGames::Uno.new, GameRoomGames::Monopoly.new, GameRoomGames::Spades.new,
  GameRoomGames::TicTacToe.new, GameRoomGames::FourInARow.new, GameRoomGames::Farkle.new].each do |game|
  players = %w[Alice Bob Carol Dave].take(game.id == 'spades' ? 4 : 2)
  env = GameRoomSimulation::Environment.new_game(game: game, players: players, seed: 1979)
  random = Random.new(45)
  120.times do
    break if env.finished? || env.events.length >= 90
    actor = env.replay.current_player || env.active_actor
    actions = env.legal_actions(actor)
    assert(!actions.empty?, "#{game.id}: fixture has no legal action")
    assert(env.step(actions[random.rand(actions.length)], actor: actor) == :ok, "#{game.id}: fixture rejected action")
  end
  repository, session, events = env.repository, env.session, env.events
  assert(events.length >= 5, "#{game.id}: fixture too short")
  original = game.method(:replay)
  calls = []
  game.define_singleton_method(:replay) do |*args|
    calls << args[1].length
    original.call(*args)
  end
  # Cold catch-up and a sequence of warm batches must both retain every
  # intermediate state, message, turn announcement and sound cue.
  [1, 7, events.length].each do |batch_size|
    cache = GameRoomPresentationReplay.new(game, repository)
    prefix = []
    cache.remember(session, original.call(session, [], repository)) unless batch_size == events.length
    events.each_slice(batch_size) do |batch|
      prefix += batch
      canonical = original.call(session, prefix, repository)
      # Visible session publication seals only its owned accepted log. The
      # presentation/simulation copies must still support incremental reducers
      # (Spades extends accepted_events in place), sounds and all intermediate states.
      GameRoomSessionContracts::ViewRevision.new(session: session, replay: canonical, repository: GameRepository.allocate)
      untouched = Marshal.dump(canonical)
      calls.clear
      transitions = cache.transitions(session, canonical, batch)
      assert(calls.empty?, "#{game.id}: repeated full replay for a warm single event") if batch_size == 1
      if game.id == 'farkle'
        expected_calls = batch_size == events.length ? [0] : []
        assert(calls == expected_calls, 'Farkle catch-up rebuilt complete prefixes instead of incremental transitions')
      end
      batch.each_with_index do |event, index|
        length = prefix.length - batch.length + index
        expected_before = original.call(session, prefix.take(length), repository)
        expected_after = original.call(session, prefix.take(length + 1), repository)
        actual = transitions.fetch(repository.event_id(event))
        expected = transition_signature(game, repository, event, expected_before, expected_after, players.first)
        observed = transition_signature(game, repository, event, *actual, players.first)
        assert(observed == expected, "#{game.id}: presentation changed at #{length + 1}")
        comparisons += 1
      end
      assert(Marshal.dump(canonical) == untouched, "#{game.id}: mutated canonical replay")
      # What a presenter does with its copy cannot damage the next cached prefix.
      transitions.values.last.last.history.clear
      assert(Marshal.dump(canonical) == untouched, "#{game.id}: final model shared with presentation")
      assert(cache.transitions(session, canonical, []).empty?, "#{game.id}: duplicate presentation")
    end
  end

  prefix, next_events = events.take(3), events.take(4)
  cache = GameRoomPresentationReplay.new(game, repository)
  cache.remember(session, original.call(session, prefix, repository))
  changed = session.merge('__control_epoch' => 2)
  calls.clear
  cache.transitions(changed, original.call(changed, next_events, repository), [next_events.last])
  assert(calls == [3], "#{game.id}: control epoch failed to invalidate prefix")
  calls.clear
  changed = changed.merge('__id' => 88)
  cache.transitions(changed, original.call(changed, events.take(5), repository), [events[4]])
  assert(calls == [4], "#{game.id}: new session failed to invalidate prefix")
  cache.remember(session, original.call(session, prefix, repository))
  previous = cache.instance_variable_get(:@previous)
  # Cached games can expose immutable authenticated logs. Construct the
  # deliberately different local prefix without editing a shared sealed row.
  previous.accepted_events = GameRoomSnapshot.copy(Array.new(previous.accepted_events))
  previous.accepted_events.first['value'] = 'stale'
  calls.clear
  cache.transitions(session, original.call(session, next_events, repository), [next_events.last])
  assert(calls == [3], "#{game.id}: differing prefix reused")

  # Serialization is an optimization, not a prerequisite for presentation.
  special = session.merge('local_callback' => -> {})
  cache.remember(special, original.call(special, prefix, repository))
  result = cache.transitions(special, original.call(special, next_events, repository), [next_events.last])
  assert(result.length == 1, "#{game.id}: uncacheable session lost transition")
end
puts "Presentation cache: #{comparisons} before/after/message/sound comparisons, invalidation, copies, nil-state boards and cold recovery passed"
