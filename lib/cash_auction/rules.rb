# frozen_string_literal: true

module GameRoomCashAuction
  module Rules
    DEFAULT_OPTIONS = {'starting_points'=>1000, 'ante'=>10, 'pass_penalty'=>200,
      'rounds'=>8, 'count_interval'=>2, 'black_chest_chance'=>5}.freeze
    CHEST_REWARDS = [100, 2500, 10_000, -100, -500, -1000, 'bankrupt'].freeze
    module_function

    def initial(players, options)
      raise ArgumentError, 'Invalid cash auction options' unless options.is_a?(Hash)
      configured = DEFAULT_OPTIONS.merge(options)
      valid_options = DEFAULT_OPTIONS.keys.all? { |key| configured[key].is_a?(Integer) && configured[key] >= 0 } &&
        configured['rounds'] > 0 && configured['count_interval'] > 0 && configured['black_chest_chance'] <= 100
      unless players.is_a?(Array) && !players.empty? && players.all? { |player| player.is_a?(String) && !player.empty? } && valid_options
        raise ArgumentError, 'Invalid cash auction setup'
      end
      count = players.length
      {players: players.map(&:dup), options: Marshal.load(Marshal.dump(configured)),
        round: 0, completed_rounds: 0, phase: :drawing,
        cash: Array.new(count, configured['starting_points']), eliminated: Array.new(count, false),
        pass_counts: Array.new(count, 0), pot: 0, contributions: Array.new(count, 0),
        passed: Array.new(count, false), leader: nil, highest: 0, auction_deadline: 0,
        bid_revision: 0, chests: Array.new(count, 0), question: nil, category: nil,
        chest: false, winner: nil, draw: false}
    end

    def active_seats(state)
      state[:players].each_index.reject { |seat| state[:eliminated][seat] }
    end
    def finished?(state); state[:phase] == :finished; end
    def time?(now); now.is_a?(Integer) && now >= 0; end
    def seat?(state, seat); seat.is_a?(Integer) && seat.between?(0, state[:players].length - 1); end
    def active?(state, seat); seat?(state, seat) && !state[:eliminated][seat]; end

    def draw!(state, category:, chest:, now:)
      return false unless %i[drawing spinning].include?(state[:phase]) && time?(now) && [true, false].include?(chest)
      begin
        owned_category = Marshal.load(Marshal.dump(category))
      rescue TypeError
        return false
      end
      ante = state[:options]['ante']
      active_seats(state).each do |seat|
        if state[:cash][seat] < ante
          state[:eliminated][seat] = true
        else
          state[:cash][seat] -= ante
          state[:pot] += ante
        end
      end
      state[:round] += 1
      state.merge!(phase: :auction, category: owned_category, chest: chest,
        contributions: Array.new(state[:players].length, 0), passed: Array.new(state[:players].length, false),
        leader: nil, highest: 0, bid_revision: 0, question: nil,
        auction_deadline: now + 3 * state[:options]['count_interval'])
      finish_round!(state) if active_seats(state).length <= 1
      true
    end

    def bid!(state, seat, amount, now:, revision:)
      return false unless state[:phase] == :auction && active?(state, seat) && !state[:passed][seat]
      return false unless time?(now) && now < state[:auction_deadline] && revision.is_a?(Integer) && revision >= 0
      return false unless amount.is_a?(Integer) && amount > state[:highest] && amount <= state[:cash][seat] + state[:contributions][seat]
      difference = amount - state[:contributions][seat]
      state[:cash][seat] -= difference
      state[:pot] += difference
      state[:contributions][seat] = amount
      state[:highest], state[:leader], state[:bid_revision] = amount, seat, revision
      state[:auction_deadline] = now + 3 * state[:options]['count_interval']
      true
    end

    def pass!(state, seat)
      return false unless state[:phase] == :auction && active?(state, seat) && !state[:passed][seat] && state[:leader] != seat
      state[:passed][seat] = true
      state[:pass_counts][seat] += 1
      if (state[:pass_counts][seat] % 3).zero?
        penalty = [state[:cash][seat], state[:options]['pass_penalty']].min
        state[:cash][seat] -= penalty
        state[:pot] += penalty
      end
      true
    end

    def award!(state, now:)
      return false unless state[:phase] == :auction && time?(now) && now >= state[:auction_deadline]
      if state[:leader] && !state[:chest]
        state[:phase] = :question_pending
      else
        state[:chests][state[:leader]] += 1 if state[:leader]
        finish_round!(state)
      end
      true
    end

    def start_question!(state, question)
      return false unless state[:phase] == :question_pending && active?(state, state[:leader]) && question.is_a?(Hash) && !question.empty?
      begin
        owned_question = Marshal.load(Marshal.dump(question))
      rescue TypeError
        return false
      end
      state[:question], state[:phase] = owned_question, :answering
      true
    end

    def answer!(state, seat, correct, now:)
      return false unless state[:phase] == :answering && active?(state, seat) && seat == state[:leader] && [true, false].include?(correct) && time?(now)
      if correct
        state[:cash][seat] += state[:pot]
        state[:pot] = 0
      elsif state[:cash][seat].zero?
        state[:eliminated][seat] = true
      end
      finish_round!(state)
      true
    end

    def finish_round!(state)
      return false unless %i[auction question_pending answering].include?(state[:phase]) && state[:completed_rounds] < state[:round]
      state[:completed_rounds] += 1
      if active_seats(state).length <= 1 || state[:completed_rounds] >= state[:options]['rounds']
        if state[:chests].any?(&:positive?)
          state[:phase] = :opening_chests
        else
          settle!(state)
        end
      else
        state[:phase] = :drawing
      end
      true
    end

    def settle!(state)
      active = active_seats(state)
      highest = active.map { |seat| state[:cash][seat] }.max
      leaders = active.select { |seat| state[:cash][seat] == highest }
      if leaders.length > 1
        state[:phase], state[:winner], state[:draw] = :drawing, nil, false
      else
        state[:phase] = :finished
        state[:winner] = leaders.empty? ? nil : state[:players][leaders.first].dup
        state[:draw] = leaders.empty?
      end
      true
    end

    def open_chest!(state, seat, reward, now:)
      return false unless state[:phase] == :opening_chests && seat?(state, seat) && state[:chests][seat] > 0 && time?(now)
      valid_reward = reward.is_a?(Integer) && CHEST_REWARDS.include?(reward) || reward.is_a?(String) && reward == 'bankrupt'
      return false unless valid_reward
      state[:chests][seat] -= 1
      if reward == 'bankrupt'
        state[:cash][seat], state[:eliminated][seat] = 0, true
      else
        state[:cash][seat] = [state[:cash][seat] + reward, 0].max
      end
      settle!(state) if state[:chests].none?(&:positive?)
      true
    end
  end
end
