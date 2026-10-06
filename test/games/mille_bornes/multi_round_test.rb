require_relative "../../support/elten_array_shuffle"
require_relative "../../support/mille_bornes"
include MilleBornesTest

test("5000-point matches including recycling conserve cards and preserve replay without safeties") do
  configurations = [{ players: %w[Alice Bob], options: {} },
   { players: %w[Alice Bob Carol David], options: { "team_count" => 2 } },
   { players: %w[Alice Bob], options: { "counterflow" => true, "counterflow_cards" => 3, "end_counterflow_cards" => 4 } }]
  configurations += configurations.map { |entry| entry.merge(options: entry[:options].merge("include_safeties" => false)) }
  configurations << { players: %w[Alice Bob Carol David], options: {
    "team_count" => 2, "include_safeties" => false, "accumulate_hazards" => true, "recycle_discard" => true
  } }
  configurations.each do |configuration|
    fixture = Fixture.new(players: configuration[:players], options: configuration[:options])
    game = fixture.game
    include_safeties = configuration[:options].fetch("include_safeties", true)
    deck_count = (include_safeties ? 106 : 102) + configuration[:options].fetch("counterflow_cards", 0) + configuration[:options].fetch("end_counterflow_cards", 0)
    expected_cards = game.send(:deck_for, configuration[:options]).sort
    initial = fixture.replay
    state = initial.state
    history = initial.history
    events = []
    completed_rounds = 0
    random = GameRoomRandom::SeededSource.new(932 + fixture.players.length)
    fixture.context.random_source = random
    6000.times do
      current = fixture.snapshot(state)
      break if current.finished?
      actor = fixture.players.first
      selection = game.automatic_action(current, actor)
      unless selection
        actor = game.active_actors(current).first
        actions = game.legal_actions(current, actor)
        selection = game.bot_strategy.choose(actions: actions, game: game, replay: current,
          actor: actor, random_source: random)
      end
      assert(selection, "unfinished default match has no decision")
      status, plan = game.action_for(selection, current, actor, context: fixture.context)
      equal(:ok, status, "default match decision")
      plan.events.each do |command|
        identifier = events.length + 1
        event = MilleBornesTest.event(identifier, actor, command.action, command.value)
        accepted = game.send(:apply_event, state, event, actor, identifier, history)
        assert(accepted, "default match event rejected")
        events << event
        if command.action == "deal"
          equal(Array.new(fixture.players.length, 6), state[:hands].values.map(&:length), "fresh six-card hands")
          expected = fixture.players[(state[:round] - 1) % fixture.players.length]
          equal(expected, state[:current_player], "round starter rotates")
          equal(0, state[:recycle_count], "new round resets stock recycling")
          assert(state[:tracks].all? { |track| track[:miles] == 0 && track[:safeties].empty? }, "new round resets tracks")
          assert(state[:tracks].none? { |track| track[:counterflow] }, "new round clears counterflow")
        end
      end
      cards = state[:hands].values.flatten + state[:draw_pile] + state[:discard] + state[:spent]
      equal(deck_count, cards.length, "full deck conserved between rounds")
      equal(deck_count, cards.uniq.length, "physical cards unique")
      equal(expected_cards, cards.sort, "exact physical deck conserved")
      unless include_safeties
        assert(state[:tracks].all? { |track| track[:safeties].empty? && track[:dirty_tricks] == 0 }, "no impossible immunity or bonus")
        assert(cards.none? { |card| game.class::SAFETIES.include?(card.split(":").first) }, "no safety reappears in later rounds or recycling")
      end
      next unless [:round_complete, :finished].include?(state[:phase])

      completed_rounds += 1
      restored = game.replay(fixture.session, events, fixture.repository)
      equal(state, restored.state, "round boundary replay")
      equal(history.map(&:to_h), restored.history.map(&:to_h), "round boundary history")
    end
    final = game.replay(fixture.session, events, fixture.repository)
    equal(state, final.state, "complete run replay")
    equal(history.map(&:to_h), final.history.map(&:to_h), "complete run history")
    equal(events.length, final.accepted_events.length, "complete multi-round history accepted")
    assert(final.finished?, "default match failed to finish within 6000 decisions")
    assert(completed_rounds >= 2, "default match did not exercise redealing")
    assert(final.state[:scores].max >= 5000, "default winning score not reached")
    puts "#{fixture.players.length} players, safeties #{include_safeties}: #{completed_rounds} rounds, #{events.length} events, winning score #{final.state[:scores].max}"
  end
end
