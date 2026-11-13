require 'json'
require_relative 'assertions'
require_relative '../../games/cash_auction'
require_relative '../../lib/game_surfaces/specifications'

module CashAuctionFixture
  class Repository
    attr_accessor :players
    def initialize(players); @players = players; end
    def players_for(_session); @players; end
    def actor_of(event, _session = nil); event.fetch('actor'); end
    def event_id(event); event.fetch('id'); end
  end

  # Native random requests come from the real game plan. Only the server's
  # drawn seed and accepted timestamp are supplied by this local fixture.
  class Match
    include GameRoomTest::Assertions
    attr_reader :game, :session, :repository, :events, :players
    attr_accessor :now

    def initialize(players: %w[Alice Bob Carol Dan], options: {}, game_id: 'cash-auction-model', epoch_shift: 0)
      @game, @players = GameRoomGames::CashAuction.new, players.dup
      @repository = Repository.new(@players)
      @session = {'__id'=>game_id, 'options'=>JSON.generate(game.table_creation_options(options)),
        'created_at'=>100 + epoch_shift, '__server_started_at'=>100}
      @now, @events, @next_id, @epoch_shift = 100 + epoch_shift, [], 1, epoch_shift
    end

    def replay; game.replay(session, events, repository); end
    def context
      GameRoomGames::ActionContext.new(now: now, server_random: true, table_owner: players.first, session_id: session['__id'])
    end
    def native_time(time = now); time - @epoch_shift; end
    def plan(selection, actor: players.first, view: replay)
      game.action_for(selection, view, actor, context: context)
    end

    def append_raw(action:, value:, actor: players.first, id: :next, created_at: :current, **extra)
      row = {'id'=>id == :next ? @next_id : id, 'actor'=>actor, 'action'=>action, 'value'=>value,
        'created_at'=>created_at == :current ? native_time : created_at}.merge(extra)
      @next_id += 1
      events << row
      row
    end

    def materialize(command, actor: players.first, seed: 1)
      request = command.respond_to?(:random_request) && command.random_request
      value, metadata = command.value, {}
      if request
        assert(seed.is_a?(Integer) && seed.between?(0, (1 << 128) - 1))
        copied = Marshal.load(Marshal.dump(request))
        assert_equal('recipe', copied['format'])
        assert_equal('seed_text', copied.dig('recipe', 'kind'))
        value = copied.fetch('recipe').fetch('template').sub('{seed}', seed.to_s(16).rjust(32, '0'))
        metadata['__server_random'] = copied
      end
      append_raw(action: command.action, value: value, actor: actor, **metadata)
    end

    def append_plan(plan, actor: players.first, seed: 1)
      count = replay.accepted_events.length
      plan.events.each { |command| materialize(command, actor: actor, seed: seed) }
      result = replay
      assert_equal(count + plan.events.length, result.accepted_events.length, 'A planned move was refused during replay')
      result
    end

    def submit(selection, actor: players.first, seed: 1)
      status, command_plan = plan(selection, actor: actor)
      assert_equal(:ok, status, "Refused #{selection.inspect} for #{actor}")
      append_plan(command_plan, actor: actor, seed: seed)
    end

    def automatic(seed: 1)
      selection = game.automatic_action(replay, players.first, context: context)
      assert(selection, "No automatic action in #{replay.state[:phase]}")
      submit(selection, seed: seed)
    end

    def begin_round(chest: false)
      assert_equal(:drawing, replay.state[:phase])
      self.now = [now, replay.state[:resume_at]].max
      chance = replay.state[:options]['black_chest_chance']
      seed = (0...10_000).find { |candidate| (Random.new(candidate).rand(100) < chance) == chest }
      assert(seed, 'No matching bounded wheel seed')
      automatic(seed: seed)
      assert_equal(:spinning, replay.state[:phase])
      self.now = replay.state[:resume_at]
      automatic
    end

    def bid(actor, amount)
      submit(bid_selection(actor, amount), actor: actor)
    end
    def bid_selection(actor, amount, view: replay)
      {'kind'=>'question', 'action'=>'submit', 'question_id'=>game.surface_spec(view, actor).id, 'answer'=>amount.to_s}
    end
    def pass(actor)
      submit({'kind'=>'question', 'action'=>'pass', 'question_id'=>game.surface_spec(replay, actor).id}, actor: actor)
    end
    def close_auction
      self.now = replay.state[:auction_deadline]
      automatic
    end
    def reveal_question(seed: 1); automatic(seed: seed); end
    def answer(actor, index)
      submit({'kind'=>'question', 'action'=>'submit', 'question_id'=>game.surface_spec(replay, actor).id,
        'answer'=>index.to_s}, actor: actor)
    end
    def answer_correct(actor)
      answer(actor, replay.state[:question].fetch(:correct_index))
    end
    def open_chest(actor, reward: 100)
      index = GameRoomGames::CashAuction::CHEST_REWARDS.index(reward)
      assert(index, 'Unknown chest reward')
      seed = (0...10_000).find { |candidate| Random.new(candidate).rand(7) == index }
      selection = game.legal_actions(replay, actor, context: context).find { |action| action['action'] == 'open_chest' }
      assert(selection, 'No owned chest action')
      submit(selection, actor: actor, seed: seed)
    end

    def question_seed_for_index(index)
      current = replay.state
      @bank ||= GameRoomCashAuction::QuestionBank.new(game.selected_content_pack(current[:options]))
      (0...1024).find do |seed|
        @bank.draw(category: current[:category], seed: seed, used: current[:used_questions])[:correct_index] == index
      end || raise('No matching bounded answer permutation seed')
    end
  end
end
