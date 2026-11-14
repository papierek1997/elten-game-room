require_relative '../../support/french_tarot'
env = FrenchTarotFixture.match(rounds: 4, seed: 81)
2000.times do
  break if env.finished?
  actions = env.legal_actions
  selected = actions.max_by { |action| env.game.bot_action_score(env.replay, env.active_actor, action) }
  raise 'No legal bot action' unless selected
  raise 'Bot action refused' unless env.step(selected) == :ok
end
raise 'Incomplete bot match' unless env.finished? && env.replay.state[:completed_deals] == 4 && env.replay.state[:scores].values.sum.zero?
puts 'PASS production French Tarot bot match, four completed deals'
