require_relative '../../support/private_card_games'
require_relative '../../../games/bouillabaisse'

game = GameRoomGames::Bouillabaisse.new
h, runners = PrivateCardGamesTest.create(game, users:%w[Alice Bob Carol])
begin
  shortened = []
  6.times do |round|
    16.times { PrivateCardGamesTest.tick(h,runners) } unless round.zero?
    first = h.replay('Alice')
    assert(first.state[:phase] == :playing, "round stalled: #{first.state[:phase]}")
    PrivateCardGamesTest.assert_private(h)
    h.users.each do |user|
      view = h.replay(user)
      state = view.state
      reminder = game.game_shortcuts(view, user).find { |shortcut| shortcut.key == 'r' && shortcut.modifiers.empty? }
      assert(reminder && reminder.message.include?("Round #{round + 1} of 6."), 'private round lost its R reminder')
      deal = view.accepted_events.reverse.find { |event| event['action'] == 'deal' }
      assert(Array(game.describe_event(deal, h.repositories[user], view, user)) == [reminder.message],
        'private deal includes unrelated rules or differs from its reminder')
      foreign_id, foreign = state[:private_draws].find { |_, draw| draw[:player] != user }
      assert_raises(EltenLink::Error) { h.view(user).pool(foreign[:pool]).draw(foreign_id) }
    end
    51.times do
      replay = h.replay('Alice')
      break unless replay.state[:phase] == :playing
      actor = replay.current_player
      assert(actor, "no turn: #{replay.state[:phase]} / #{replay.state[:private_error]}")
      action = game.legal_actions(h.replay(actor), actor).first
      PrivateCardGamesTest.submit(h,runners,actor,action)
      PrivateCardGamesTest.assert_private(h)
    end
    pending = h.replay('Alice').state
    if pending[:phase] == :private_show
      shortened << round + 1
      assert([2, 3, 4].include?(round + 1), 'unneeded disclosure during a complete scoring round')
      assert(pending[:tournament_checkpoint]['index'] == round, 'points were published before remaining cards were audited')
      assert(pending[:private_draws].values.any? { |draw| draw[:initial] && draw[:used].size < draw[:count] }, 'fixture did not retain private receipts')
    end
    16.times do
      break unless h.replay('Alice').state[:phase] == :private_show
      PrivateCardGamesTest.tick(h,runners)
    end
    state = h.replay('Alice').state
    assert(!state[:private_error], "audit error: #{state[:private_error]}")
    assert(state[:phase] == (round == 5 ? :finished : :round_complete), "round failed: #{state[:phase]}")
    assert(state[:tournament_checkpoint]['index'] == round+1, 'unaudited score checkpoint')
  end
  assert(shortened.include?(4), 'no shortened special-card round exercised')
  assert(h.events('Alice').size == h.replay('Alice').accepted_events.size, 'private event rejected')
  puts 'PASS Bouillabaisse private: 3 account-owned hands, inaccessible foreign draws, 6 fully audited rounds, final result'
ensure
  runners.each_value(&:close)
end
