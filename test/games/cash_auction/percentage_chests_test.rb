require_relative '../../support/cash_auction'
require_relative '../../../lib/game_event_presentation'
require_relative '../../../lib/game_sounds'
require_relative '../../../lib/game_event_presenter'

module CashAuctionPercentageChestsTest
  extend GameRoomTest::Assertions
  R = GameRoomCashAuction::Rules
  F = CashAuctionFixture::Match
  module_function

  class Draws
    def initialize(sign, magnitude); @values = [[10, sign], [140, magnitude]]; end
    def rand(limit)
      expected, value = @values.shift
      raise 'Unexpected random draw' unless expected == limit
      value
    end
  end

  def opening(cash:, chests:, eliminated: nil)
    state = R.initial(%w[Alice Bob], 'auction_rules_version'=>3)
    state.merge!(phase: :opening_chests, cash: cash.dup, chests: chests.dup,
      eliminated: eliminated || [false, false], chest_base_cash: cash.dup,
      chest_percentages: [0, 0], open_chests_at: 5)
    state
  end

  class Outcomes
    def initialize(rewards)
      @draws = rewards.flat_map do |reward|
        if reward.zero?
          [[10, 9]]
        else
          index = [5, 10, 15, 20, 25, 30, 35].index(reward.abs)
          [[10, reward.positive? ? 0 : 6], [140, [49, 36, 25, 16, 9, 4, 1].take(index).sum]]
        end
      end
    end
    def rand(limit)
      expected, value = @draws.shift
      raise 'Unexpected batch random draw' unless expected == limit
      value
    end
  end

  def open_all(state, rewards)
    assert(R.open_chests!(state, random_source: Outcomes.new(rewards), now: 5))
  end

  def distribution
    counts = Hash.new(0)
    10.times do |sign|
      140.times do |magnitude|
        state = R.initial(%w[Alice Bob], 'auction_rules_version'=>3)
        counts[R.chest_reward(state, random_source: Draws.new(sign, magnitude))] += 1
      end
    end
    [5, 10, 15, 20, 25, 30, 35].zip([49, 36, 25, 16, 9, 4, 1]).each do |value, weight|
      assert_equal(6 * weight, counts[value], "Wrong probability for +#{value}%")
      assert_equal(3 * weight, counts[-value], "Wrong probability for -#{value}%")
    end
    assert_equal(140, counts[0])
    assert_equal(1400, counts.values.sum)
    assert_equal(5040, counts.sum { |value, count| value * count })
  end

  def settlement
    [[20, -10, 0], [-10, 20, 0]].each do |rewards|
      state = opening(cash: [10000, 10500], chests: [2, 1])
      open_all(state, rewards)
      assert_equal([11000, 10500], state[:cash])
      assert_equal('Alice', state[:winner])
      assert_equal([10, 0], state[:chest_percentages])
      assert_equal([0, 0], state[:chests])
    end
    state = opening(cash: [1, 10], chests: [2, 1])
    open_all(state, [35, 35, 5])
    assert_equal([2, 11], state[:cash], 'Round only once using exact integer arithmetic')
    state = opening(cash: [1000, 20], chests: [3, 1])
    open_all(state, [-35, -35, -35, 0])
    assert_equal([0, 20], state[:cash])
    assert_equal('Bob', state[:winner])
    state = opening(cash: [10000, 20], chests: [1, 0], eliminated: [true, false])
    open_all(state, [35])
    assert_equal([true, false], state[:eliminated])
    assert_equal('Bob', state[:winner], 'A chest revived an eliminated player')
    state = opening(cash: [100, 110], chests: [1, 1])
    open_all(state, [10, 0])
    assert_equal([:drawing, nil, [110, 110]], state.values_at(:phase, :winner, :cash))
    assert(R.draw!(state, category: 0, chest: false, now: 6))
    assert(R.bid!(state, 0, 1, now: 7, revision: 1))
    assert(R.award!(state, now: state[:auction_deadline]))
    assert(R.start_question!(state, {correct_index: 0}))
    assert(R.answer!(state, 0, true, now: state[:auction_deadline]))
    assert_equal([120, 100], state[:cash], 'The percentage was reapplied after a tiebreak')
  end

  def refusals
    state = opening(cash: [100, 200], chests: [1, 1])
    before = Marshal.dump(state)
    assert_equal(false, R.open_chests!(state, random_source: nil, now: 4))
    assert_equal(false, R.open_chest!(state, 0, 5, now: 5))
    assert_equal(before, Marshal.dump(state), 'An early or manual opening changed the game')
    open_all(state, [0, 0])
    before = Marshal.dump(state)
    assert_equal(false, R.open_chests!(state, random_source: nil, now: 6))
    assert_equal(before, Marshal.dump(state), 'The same batch was opened twice')
  end

  def match
    f = F.new(rules_version: 3, players: %w[Alice Bob],
      options: {'content_language_id'=>'en', 'pass_penalty'=>0})
    %w[Alice Alice Bob].each do |player|
      f.begin_round(chest: true)
      f.bid(player, 1)
      f.close_auction
    end
    8.times do |index|
      player = f.players[index % 2]
      f.begin_round
      f.bid(player, 1)
      f.close_auction
      f.reveal_question
      f.answer_correct(player)
    end
    assert_equal(:opening_chests, f.replay.state[:phase])
    f
  end

  def production_replay
    f = match
    base = f.replay.state[:cash].dup
    deadline = f.replay.state[:open_chests_at]
    assert_equal(f.now + 5, deadline)
    assert_equal([], f.game.active_actors(f.replay), 'A player was asked to open a chest')
    assert_equal([], f.game.legal_actions(f.replay, 'Alice', context: f.context))
    assert_equal(GameSurfaces::QuestionSpec, f.game.surface_spec(f.replay, 'Alice').class)
    f.now = deadline - 1
    assert_equal(nil, f.game.automatic_action(f.replay, 'Alice', context: f.context))
    before = f.replay
    f.append_raw(action: 'open_chests', actor: 'Alice', value: 'forged')
    assert_equal(before, f.replay, 'An unproved batch seed changed the game')
    f.now = deadline
    selection = f.game.automatic_action(f.replay, 'Alice', context: f.context)
    assert_equal('open_chests', selection['action'])
    assert_equal(:invalid, f.plan(selection, actor: 'Bob').first)
    seed = (0...100000).find do |candidate|
      random = Random.new(candidate)
      Array.new(3) { R.chest_reward(f.replay.state, random_source: random) } == [20, -10, 0]
    end
    assert(seed, 'No matching bounded chest seed')
    result = f.automatic(seed: seed)
    assert_equal([[0, 20], [0, -10], [1, 0]], result.state[:last_chest_rewards])
    assert_equal([(base[0] * 110 + 50) / 100, base[1]], result.state[:cash])
    assert_equal('Alice', result.winner)
    assert_equal(result.state[:cash], f.game.participant_scores(result).values)
    assert_equal(false, result.state.key?(:bonus_prizes))
    assert_equal(result, GameRoomGames::CashAuction.new.replay(f.session, f.events, f.repository))
    event = f.events.last
    stages = f.game.event_presentation_stages(event, f.repository, before, result, 'Alice')
    assert_equal(4, stages.length)
    assert_equal(['Opening the black chests!'], stages[0][:descriptions])
    assert_equal([], stages[1][:descriptions])
    assert_equal(true, stages[1][:wait_for_sounds])
    assert_equal(4.0, stages[2][:delay])
    assert(stages[2][:descriptions].any? { |text| text.include?('+20%') })
    assert(stages[2][:descriptions].any? { |text| text.include?('-10%') })
    cues = stages.map do |stage|
      f.game.event_sound_cues(event: event, before_replay: before, after_replay: result,
        history: stage[:history], viewer: 'Alice', random_variant: nil)
    end
    assert_equal([nil, 'auction_chest', nil, nil], cues)
    # Drive the same queue used by GameEventPresenter. Result audio belongs
    # to the final empty stage, not to the contents stage before its pause.
    native_cues = stages.each_with_index.map do |stage, index|
      GameRoomSounds.event_cue(game: f.game, event: event, before_replay: before,
        after_replay: result, repository: f.repository, viewer: 'Alice',
        history: stage[:history], include_result: index == stages.length - 1)
    end
    assert_equal([nil, 'auction_chest', nil, 'win_party'], native_cues)
    now, log = 0.0, []
    done = false
    sound = Object.new
    sound.define_singleton_method(:finished?) { done }
    sound.define_singleton_method(:length) { 2.0 }
    queue = GameRoomEventPresentation.new(clock: -> { now }, initial_replay: before)
    stages.each_with_index do |stage, index|
      queue.enqueue(replay: result, defer_replay: true, delay: stage.fetch(:delay, 0),
        wait_for_sounds: stage.fetch(:wait_for_sounds, false),
        start: -> { log << index; index == 1 ? sound : nil },
        finish: index == 3 ? -> { log << :result } : nil)
    end
    queue.advance
    assert_equal([0], log)
    now = 1.0
    queue.advance
    assert_equal([0, 1], log)
    now = 1.5
    queue.advance
    assert_equal([0, 1], log, 'Contents overlapped the chest sound')
    done = true
    queue.advance
    assert_equal([0, 1, 2], log)
    now = 5.499
    queue.advance
    assert_equal([0, 1, 2], log, 'Result preceded the complete four-second pause')
    now = 5.5
    queue.advance
    assert_equal([0, 1, 2, 3, :result], log)
    assert_equal(false, queue.busy?)
    queue.close
    now, spoken, played = 0.0, [], []
    done = false
    original = GameRoomSounds.method(:play)
    GameRoomSounds.define_singleton_method(:play) do |_program, cue, **|
      played << cue
      cue == 'auction_chest' ? sound : nil
    end
    presenter = GameRoomEventPresenter.new(game: -> { f.game }, repository: -> { f.repository },
      program: -> { Object.new }, viewer: -> { 'Alice' }, client: -> { nil },
      surface_state: -> { {} }, clock: -> { now }, covered: -> { false },
      speech: ->(text) { spoken << text }, trace: ->(*) {}, history_changed: ->(*) {},
      session_changed: -> {})
    begin
      presenter.process_new_events(before, session: f.session)
      presenter.process_new_events(result, session: f.session)
      assert(presenter.event_presentation, 'The production presenter did not enable staged opening')
      assert_equal(['Opening the black chests!'], spoken)
      assert_equal([], played)
      now = 1.0
      presenter.event_presentation.advance
      assert_equal(['auction_chest'], played)
      assert_equal(['Opening the black chests!'], spoken)
      done = true
      now = 1.5
      presenter.event_presentation.advance
      assert(spoken.any? { |text| text.include?('+20%') })
      assert(!spoken.include?(f.game.result_text(result)), 'The real presenter announced an early result')
      now = 5.499
      presenter.event_presentation.advance
      assert_equal(['auction_chest'], played)
      now = 5.5
      presenter.event_presentation.advance
      assert_equal(['auction_chest', 'win_party'], played)
      assert_equal(f.game.result_text(result), spoken.last)
    ensure
      presenter.event_presentation&.close
      GameRoomSounds.define_singleton_method(:play, original)
    end
  end

  def run
    assert_equal(R::CURRENT_VERSION, GameRoomGames::CashAuction.new.table_creation_options['auction_rules_version'])
    distribution
    settlement
    refusals
    production_replay
    puts 'PASS percentage chests: exact 60/30/10 weighted draws, shared base, one rounding, floor, automatic five-second opening, ordered sound/rewards, four-second result pause, tie, elimination and cold replay'
  end
end

CashAuctionPercentageChestsTest.run
