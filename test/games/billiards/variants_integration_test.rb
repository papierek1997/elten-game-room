require_relative '../../support/billiards'
require_relative '../../support/session_runner'

module BilliardsVariantsIntegrationTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  MODES = %w[ten straight one_pocket bank_short bank_full cutthroat blackball english carom one_cushion three_cushion pyramid].freeze

  def self.match(id)
    BilliardsFixture::Match.new(players: id == 'cutthroat' ? %w[Alice Bob Carol] : %w[Alice Bob],
      options: {'discipline'=>id, 'rack_seed'=>43, 'point_target'=>10})
  end
  def self.prepare(value)
    8.times do
      replay = value.replay
      break if replay.state[:choices].empty?
      replay.state[:choices].each { |id| assert(!B::MatchPresentation.choice(id, replay.state[:decision]).empty?) }
      value.submit('choice', {'choice'=>0})
    end
    replay = value.replay
    assert_equal([], replay.state[:choices], 'Preparation did not reach a playable shot')
    cue = replay.state[:balls].find { |b| b.id == B::Rules.cue_id(replay.state) }
    if !cue.on_table? || replay.state[:hand] && !B::Rules.placement?(replay.state, cue.id, cue.x, cue.y)
      position = B::Rules.find_placement(replay.state)
      assert(position, 'No legal dynamic cue placement')
      value.submit('place', {'ball'=>cue.id, 'x'=>position[0], 'y'=>position[1]})
    end
    value.replay
  end
  def self.run
    shared_game = GameRoomGames::Billiards.new
    MODES.each do |id|
      value = match(id)
      replay = value.replay
      assert_equal(id, replay.state[:options]['discipline'], "#{id}: normalized to another game")
      players = id == 'cutthroat' ? 3 : 2
      assert_equal(nil, value.game.options_error(replay.state[:options], player_count: players))
      assert(value.game.options_error(replay.state[:options], player_count: players == 3 ? 2 : 3), "#{id}: wrong roster accepted")
      assert(B::Rules.engine(replay.state[:options]), "#{id}: option has no engine")
      assert_equal((0...replay.state[:balls].length).to_a, replay.state[:balls].map(&:id))
      assert(!B::MatchPresentation.status(replay.state).empty?, "#{id}: missing initial status")
      replay = prepare(value)
      value.game.legal_actions(replay, replay.current_player).each do |action|
        assert_equal(:ok, value.game.action_for(action, replay, replay.current_player).first, "#{id}: advertised action was invalid: #{action.inspect}")
      end
      selection = value.game.legal_actions(replay, replay.current_player).find { |a| a['action'] == 'shot' }
      assert(selection, "#{id}: no actual shot entry point")
      assert_equal(B::Rules.cue_id(replay.state), selection['cue'])
      assert_equal([], selection['rails'])
      shot = selection.merge('shot'=>selection['shot'].merge('power'=>1))
      assert_equal(:invalid, value.game.action_for(shot.merge('cue'=>99), replay, replay.current_player).first, "#{id}: forged cue accepted")
      assert_equal(:invalid, value.game.action_for(shot.merge('revision'=>replay.state[:revision] - 1), replay, replay.current_player).first)
      assert_equal(:invalid, value.game.action_for(shot.merge('rails'=>Array.new(13, 0)), replay, replay.current_player).first, "#{id}: unbounded bank plan")
      assert_equal(:invalid, value.game.action_for(shot.merge('rails'=>[4]), replay, replay.current_player).first)
      status, plan = value.game.action_for(shot, replay, replay.current_player)
      assert_equal(:ok, status)
      wire = JSON.parse(plan.events.first.value)
      assert_equal(3, wire.first)
      assert_equal(selection['cue'], wire[9])
      assert_equal(11, wire.length)
      assert(plan.events.first.value.bytesize <= 64)
      previous_count = replay.accepted_events.length
      after = value.submit('shot', shot.reject { |key, _| %w[kind action revision].include?(key) })
      assert_equal(previous_count + 1, after.accepted_events.length, "#{id}: acknowledged shot was not replayed")
      assert(!B::MatchPresentation.ruling(after.state).empty?)
      assert(!B::MatchPresentation.status(after.state).empty?)
      after.state[:choices].each { |choice| assert(!B::MatchPresentation.choice(choice, after.state[:decision]).empty?) }
      cold = GameRoomGames::Billiards.new.replay(value.session, value.events, value.repository)
      assert_equal(after, cold, "#{id}: cold replay differs from warm reducer")
      assert_equal(cold, shared_game.replay(value.session, value.events, value.repository), "#{id}: reused game leaked another mode's cache")
      snapshot = Marshal.dump(cold)
      after.state[:scores][0] = 999
      after.state[:balls].first.x = -100
      after.state[:choices] << 'foreign_decision'
      assert_equal(snapshot, Marshal.dump(value.replay), "#{id}: a view mutated the retained replay")
      # A different native session identity cannot inherit a previous model.
      another = value.session.merge('__id'=>"#{id}-other-session")
      assert_equal(GameRoomGames::Billiards.new.replay(another, [], value.repository), shared_game.replay(another, [], value.repository))
    end
    english_second_cue
    prediction_profiles
    score_penalties
    bank_wire_round_trip
    executor_bots
    puts 'Billiards variants integration: twelve advanced modes, correct 2/3-seat rosters, wire3 cold replay and bitpacked bank plans, malformed cue/rail/revision refusal, copied replay caches, active executor bots with acknowledged shots and converged clients passed.'
  end

  def self.english_second_cue
    value = match('english')
    replay = prepare(value)
    selection = value.game.legal_actions(replay, replay.current_player).find { |a| a['action'] == 'shot' }
    value.submit('shot', selection.reject { |key, _| %w[kind action revision].include?(key) }.merge('shot'=>value.shot.merge('power'=>1)))
    replay = prepare(value)
    assert_equal('Bob', replay.current_player)
    assert_equal(1, B::Rules.cue_id(replay.state))
    selection = value.game.legal_actions(replay, 'Bob').find { |a| a['action'] == 'shot' }
    assert_equal(1, selection['cue'])
    assert_equal(:invalid, value.game.action_for(selection.merge('cue'=>0), replay, 'Bob').first, 'Bob was allowed to strike Alice\'s physical cue')
    assert_equal(:ok, value.game.action_for(selection.merge('shot'=>value.shot.merge('power'=>1)), replay, 'Bob').first)
    spec = value.game.surface_spec(replay, 'Bob')
    assert_equal(1, spec.rules[:turn])
    assert_equal([0, 1, 2], spec.balls.map(&:id))
    assert(B::MatchPresentation.status(replay.state).include?('Ball 1, yellow'))
  end

  def self.prediction_profiles
    shot = {'angle'=>0, 'power'=>300, 'top'=>0, 'side'=>0}
    english = [B::Ball.new(id: 0, x: 0.5, y: 1.4), B::Ball.new(id: 1, x: 0.4, y: 0.6), B::Ball.new(id: 2, x: 1.1, y: 0.6)]
    snapshot = Marshal.dump(english)
    result = B::Physics.simulate(B::Table.new(discipline: 'english'), english, shot, cue_id: 1)
    assert(B::Presentation.object_prediction(result, 2, discipline: 'english').start_with?('Ball 2, red:'))
    assert(B::Presentation.summary(result, discipline: 'english', cue_id: 1).include?('Ball 2, red'))
    assert_equal(snapshot, Marshal.dump(english), 'Prediction changed the original English balls')
    pyramid = [B::Ball.new(id: 0, x: 0.5, y: 1.4), B::Ball.new(id: 1, x: 0.4, y: 0.6), B::Ball.new(id: 2, x: 1.1, y: 0.6)]
    result = B::Physics.simulate(B::Table.new(discipline: 'pyramid'), pyramid, shot, cue_id: 1)
    assert(B::Presentation.object_prediction(result, 2, discipline: 'pyramid').start_with?('Ball 2, white:'))
    assert_equal('Ball 0, coloured', B::Presentation.ball(0, discipline: 'pyramid'))
  end

  def self.score_penalties
    value = match('straight')
    replay = prepare(value)
    selection = value.game.legal_actions(replay, replay.current_player).find { |a| a['action'] == 'shot' }
    after = value.submit('shot', selection.reject { |key, _| %w[kind action revision].include?(key) }.merge('shot'=>value.shot.merge('power'=>1)))
    assert_equal(-2, after.state[:scores][0])
    assert(B::MatchPresentation.ruling(after.state).include?('Point penalty: 2.'))
  end

  def self.bank_wire_round_trip
    value = match('bank_short')
    replay = prepare(value)
    selection = value.game.legal_actions(replay, replay.current_player).find { |a| a['action'] == 'shot' }
    # The first tiny stroke is an illegal break. Accepting it reaches the
    # ordinary call phase, where an ordered bank plan can be authenticated.
    value.submit('shot', selection.reject { |key, _| %w[kind action revision].include?(key) }.merge('shot'=>value.shot.merge('power'=>1)))
    replay = prepare(value)
    rails = [0, 1, 2, 3, 0, 2, 1, 3, 2, 0, 3, 1]
    selection = value.game.legal_actions(replay, replay.current_player).find { |a| a['action'] == 'shot' }
      .merge('rails'=>rails, 'shot'=>value.shot.merge('power'=>1))
    status, plan = value.game.action_for(selection, replay, replay.current_player)
    assert_equal(:ok, status)
    wire = JSON.parse(plan.events.first.value)
    assert_equal(11, wire.length)
    assert_equal(rails.inject(1) { |packed, rail| (packed << 2) | rail }, wire[10])
    assert(plan.events.first.value.bytesize <= 64)
    prefix = Marshal.load(Marshal.dump(value.events))
    [0, -1, 1 << 26].each do |packed|
      malformed = wire.dup
      malformed[10] = packed
      events = prefix + [{'id'=>prefix.length + 1, 'actor'=>replay.current_player, 'action'=>'shot', 'value'=>JSON.generate(malformed)}]
      refused = GameRoomGames::Billiards.new.replay(value.session, events, value.repository)
      assert_equal(replay, refused, "Invalid packed bank rails were admitted: #{packed}")
    end
    malformed = wire + [0]
    events = prefix + [{'id'=>prefix.length + 1, 'actor'=>replay.current_player, 'action'=>'shot', 'value'=>JSON.generate(malformed)}]
    assert_equal(replay, GameRoomGames::Billiards.new.replay(value.session, events, value.repository), 'Variable-length wire3 was admitted')
    after = value.submit('shot', selection.reject { |key, _| %w[kind action revision].include?(key) })
    assert_equal(replay.accepted_events.length + 1, after.accepted_events.length)
    assert_equal(after, GameRoomGames::Billiards.new.replay(value.session, value.events, value.repository))
    # Transport byte limits must be checked before returning an action plan.
    huge = Marshal.load(Marshal.dump(replay))
    huge.state[:revision] = 10**80
    assert_equal(:invalid, value.game.action_for(selection.merge('revision'=>huge.state[:revision]), huge, huge.current_player).first)
  end

  def self.executor_bots
    runner = nil
    MODES.each do |id|
      game = GameRoomGames::Billiards.new
      count = id == 'cutthroat' ? 3 : 2
      options = game.normalize_options('discipline'=>id, 'bot_delay'=>0, 'bot_skill'=>'easy', 'rack_seed'=>123, 'point_target'=>100)
      harness = NativeRoomHarness.new(game: game, users: %w[Alice Observer], bots: count, options: options)
      harness.users.each { |user| harness.as(user) { harness.transports[user].set_observer(harness.table, true, actor: user) } }
      bots = harness.transports['Alice'].room_snapshot(harness.table)[:bots]
      session = harness.as('Alice') do
        harness.repositories['Alice'].start_session(table: harness.table, game: game.id, players: bots,
          options: JSON.generate(options), recipients: harness.users)
      end
      harness.instance_variable_set(:@session, session)
      runner = runner_for(harness)
      writes = []
      commit = runner.method(:commit)
      runner.define_singleton_method(:commit) do |selection, actor, **args|
        result = commit.call(selection, actor, **args)
        writes << [selection.dup, actor, result.first]
        result
      end
      if id == 'english'
        # A known missed opening stroke creates a deterministic incoming-seat
        # boundary; decisions, placement and cue1 shot then use real planning.
        replay = harness.replay('Alice')
        first = game.legal_actions(replay, bots.first).find { |a| a['action'] == 'shot' }
        result = harness.as('Alice') do
          runner.submit(session: session, replay: replay, selection: first.merge('shot'=>first['shot'].merge('power'=>1)),
            actor: bots.first, controller: true)
        end
        assert_equal(:ok, result.first)
      end
      48.times do
        runner.publish_view(session: session, replay: harness.replay('Alice'), busy: false, context: GameRoomGames::ActionContext.new)
        step(harness, runner)
        replay = harness.replay('Alice')
        second_cue = writes.any? { |selection, _, status| status == :ok && selection['action'] == 'shot' && selection['cue'] == 1 }
        break if replay.finished? || replay.state[:shots] >= 2 && (id != 'english' || second_cue)
      end
      replay = harness.replay('Alice')
      assert(writes.all? { |_, _, status| status == :ok }, "#{id}: executor refusals #{writes.map(&:last).inspect}")
      assert(replay.state[:shots] >= 2, "#{id}: real planner stalled after #{replay.state[:shots]} shots: #{writes.inspect}")
      assert(writes.any? { |selection, _, _| selection['action'] == 'shot' && selection['cue'] == 1 }, 'English executor did not write the incoming yellow cue shot') if id == 'english'
      assert(replay.accepted_events.select { |event| event['action'] == 'shot' }.all? { |event| JSON.parse(event['value']).first == 3 && event['value'].bytesize <= 64 })
      harness.assert_converged("#{id} variant executor")
      runner.close
      runner = nil
    end
  ensure
    runner&.close
  end
end
BilliardsVariantsIntegrationTest.run if $PROGRAM_NAME == __FILE__
