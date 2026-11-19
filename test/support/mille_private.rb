require_relative 'private_card_games'
require_relative '../../games/mille_bornes'

module MillePrivateTest
  module_function

  def create(users: %w[Alice Bob], options: {}, opening: nil, clock: nil)
    marker = {'publication_ref' => {'author' => users.first, 'publication_key' => 'private-test'},
      'schedule_id' => 'a' * 64, 'match_id' => 'b' * 64, 'leg' => 1}
    game = GameRoomGames::MilleBornes.new
    h = NativeRoomHarness.new(game: game, users: users, tournament: marker,
      options: game.default_options.merge('bot_delay' => 0, 'target_score' => 100).merge(options), clock: clock)
    h.start
    runners = users.to_h { |user| [user, runner_for(h, user)] }
    step(h, runners[users.first], users.first)
    if opening
      pool = h.view(users.first).pool_data_store.values.first
      cards = game.send(:deck_for, h.replay(users.first).state[:options])
      indexes = opening.map { |card| cards.index(card).to_i + 1 }
      assert(indexes.uniq.size == indexes.size && opening.all? { |c| cards.include?(c) }, 'invalid test deal')
      pool[:remaining] = indexes + (pool[:remaining] - indexes)
    end
    16.times { tick(h, runners) }
    assert(h.replay(users.first).state[:phase] == :awaiting_draw, 'private opening stalled')
    [h, runners]
  end

  def tick(h, runners)
    PrivateCardGamesTest.tick(h, runners)
  end

  def move(h, runners, user, action, card: nil, target: nil)
    replay = h.replay(user)
    choice = h.game.legal_actions(replay, user).find do |item|
      item['action'] == action && (!card || item['card'] == card) && (!target || item['target'] == target)
    end
    assert(choice, "No #{action} #{card} for #{user}: #{replay.state[:phase]}")
    h.as(user) do
      result = runners[user].submit(session: h.session, replay: replay, selection: choice, actor: user)
      assert(result.first == :ok, "#{action} rejected: #{result.first}")
    end
    tick(h, runners)
  end

  def assert_private(h)
    states = h.users.map do |user|
      replay = h.replay(user)
      assert(!replay.state[:private_error], "private failure: #{replay.state[:private_error]}")
      assert(replay.state[:hands][user].none? { |c| c.start_with?('hidden:') }, 'missing own hand')
      h.users.reject { |p| p == user }.each do |other|
        assert(replay.state[:hands][other].all? { |c| c.start_with?('hidden:') }, 'foreign hand leaked')
      end
      public = replay.state.reject { |key, _| key.to_s.start_with?('private_') || key == :hands }
      public.merge(hand_counts: replay.state[:hands].transform_values(&:size))
    end
    assert(states.uniq.length == 1, 'public state diverged')
    assert(h.users.map { |user| h.events(user) }.uniq.length == 1, 'public history diverged')
  end
end
