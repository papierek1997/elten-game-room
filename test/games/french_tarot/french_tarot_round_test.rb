require_relative '../../support/french_tarot'
%w[petite garde garde_sans garde_contre].each do |contract|
  env = FrenchTarotFixture.match
  FrenchTarotFixture.finish(env, contract: contract)
  state = env.replay.state
  raise 'Not all cards were counted' unless state[:piles].flatten(1).sum { |card| GameRoomGames::FrenchTarotScoring.half_points(card) } == 182
  raise 'Contract changed the zero-sum score' unless state[:scores].values.sum.zero?
  defenders = state[:scores].reject { |player, _| player == state[:taker] }.values
  raise 'Unequal defenders' unless defenders.uniq.one? && state[:scores][state[:taker]] == -3 * defenders.first
  scores = env.game.participant_scores(env.replay)
  raise 'The user list displays internal half-points' unless scores.all? { |player, points| points * 2 == state[:scores][player] }
  raise 'Missing contract explanation' unless env.replay.history.any? { |entry| entry.kind == :score && entry.text.include?('Required:') }
end
puts 'PASS production French Tarot four contracts and all 78 cards counted'
