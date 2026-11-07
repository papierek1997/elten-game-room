require_relative '../../support/private_card_games'
require_relative '../../../games/bridge'

game = GameRoomGames::Bridge.new
users = %w[Alice Bob Carol Dave]
%w[rubber imp mp].each do |variant|
  options = variant == 'rubber' ? {} : {'variant'=>'duplicate', 'scoring'=>variant, 'boards'=>4}
  h, runners = PrivateCardGamesTest.create(game, users: users, options: options)
  begin
    first = h.replay('Alice')
    assert(first.state[:phase] == :bidding, "opening stalled: #{first.state[:phase]}")
    PrivateCardGamesTest.assert_private(h)
    original = users.to_h { |user| [user, h.replay(user).state[:hands].fetch(user).dup] }
    assert(original.values.flatten.uniq.size == 52, 'not a complete private deck')
    assert(h.events('Alice').count { |event| event['__server_random'] } == 1, 'missing public dealer draw')
    users.each do |user|
      state = h.replay(user).state
      assert(state[:initial_hands].flatten.empty?, 'public seed retained initial cards')
      points = GameRoomGames::BridgeRules.high_card_points(original.fetch(user))
      surface = game.surface_spec(h.replay(user), user)
      surface = surface.parts.find { |part| part.id == 'cards' }.surface if surface.is_a?(GameSurfaces::CompositeSpec)
      own_zone = surface.zones.find { |zone| zone.id == 'hand' }
      assert(own_zone.header == "Your hand, high card points: #{points}", 'Own private cards did not supply the header')
      observer_view = game.game_view_spec(h.replay(user), 'Observer')
      assert(observer_view.surface.is_a?(GameSurfaces::QuestionSpec), 'An observer received more than the auction status')
      users.reject { |other| other == user }.each do |other|
        receipt = state[:private_draws].find { |_, draw| draw[:player] == other }
        assert_raises(EltenLink::Error) { h.view(user).pool(receipt.last[:pool]).draw(receipt.first) }
      end
    end

    4.times do |index|
      actor = h.replay('Alice').current_player
      PrivateCardGamesTest.submit(h, runners, actor,
        {'kind'=>'command', 'action'=>'call', 'call'=>index.zero? ? '1N' : 'P'})
    end
    state = h.replay('Alice').state
    declarer = state[:seats][state[:contract].declarer]
    dummy = state[:seats][GameRoomGames::BridgeRules.partner_of(state[:contract].declarer)]
    assert(!state[:dummy_visible], 'dummy shown before opening lead')
    leader = state[:current_player]
    action = game.legal_actions(h.replay(leader), leader).first
    PrivateCardGamesTest.submit(h, runners, leader, action)
    assert(h.replay('Alice').state[:phase] == :private_show, 'opening lead did not request dummy')
    assert(!h.replay('Alice').state[:dummy_visible], 'unproved dummy shown')
    4.times { PrivateCardGamesTest.tick(h, runners) }
    users.each do |user|
      state = h.replay(user).state
      assert(state[:dummy_visible], 'proved dummy hidden')
      assert(state[:hands][dummy].sort == original[dummy].sort, 'wrong dummy cards')
      assert(state[:current_player] == declarer, 'dummy not controlled by declarer')
      message = game.game_shortcuts(h.replay(user), user).find { |item| item.key == 'd' }.message
      assert(message.include?('Dummy') && !message.include?('You are dummy.'), 'D did not read exposed cards')
    end
    PrivateCardGamesTest.assert_private(h)
    dummy_action = game.legal_actions(h.replay(declarer), declarer).first
    (users - [declarer] + ['Observer']).each do |wrong|
      assert(game.action_for(dummy_action, h.replay('Alice'), wrong).first != :ok, 'wrong actor controls dummy')
    end
    PrivateCardGamesTest.submit(h, runners, declarer, dummy_action)

    50.times do
      replay = h.replay('Alice')
      actor = replay.current_player
      assert(actor, "play stalled: #{replay.state[:phase]} #{replay.state[:private_error]}")
      action = game.legal_actions(h.replay(actor), actor).first
      PrivateCardGamesTest.submit(h, runners, actor, action)
      PrivateCardGamesTest.assert_private(h)
    end
    state = h.replay('Alice').state
    assert(state[:phase] == :round_complete && !state[:private_error], "audit failed: #{state[:private_error]}")
    assert(state[:deals].size == 1 && state[:completed_tricks].size == 13, 'wrong completed board')
    assert(state[:initial_hands].map(&:sort) == state[:seats].map { |player| original[player].sort },
      'audit initial cards differ')
    assert(h.events('Alice').size == h.replay('Alice').accepted_events.size, 'accepted wire action lost')
    assert(users.map { |user| h.replay(user).state[:scores] }.uniq.size == 1, 'scores diverged')
    scores = h.replay('Alice').history.select { |entry| entry.kind == :score }
    assert(scores.size == 1, 'board score missing or duplicated')
    puts "PASS Bridge private #{variant}: four owners, 52 cards, dummy proof/control, full board audit"
  ensure
    runners.each_value(&:close)
  end
end
