require_relative '../../support/french_tarot'
env = FrenchTarotFixture.match(rounds: 2)
first = env.active_actor
4.times { raise unless env.step(env.legal_actions.find { |a| a['choice'] == 'pass' }) == :ok }
raise 'Redeal did not rotate the dealer' unless env.active_actor == env.players[(env.players.index(first) + 1) % 4]
raise 'All-pass deal affected scores or limit' unless env.replay.state[:scores].values.all?(&:zero?) && env.replay.state.fetch(:completed_deals, 0).zero?
FrenchTarotFixture.finish(env, contract: 'garde_sans')
raise 'Wrong deal count or settlement' unless env.finished? && env.replay.state[:completed_deals] == 2 && env.replay.state[:scores].values.sum.zero?
puts 'PASS production French Tarot all-pass redeal, dealer rotation and two-deal settlement'
