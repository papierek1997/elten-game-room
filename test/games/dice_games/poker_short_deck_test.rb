require_relative "../../../games/poker"
require_relative "../../support/private_simulation"

game = GameRoomGames::Poker.new
raise 'Full-deck storage changed' if game.normalize_options({}).key?('deck')
raise 'Wrong short deck' unless game.poker_deck('deck'=>'nine').size == 24 && game.poker_deck('deck'=>'nine').all? { |card| card.match?(/\A[9TJQKA][CDHS]\z/) }
raise 'Impossible five-card roster accepted' unless game.validation_error({'deck'=>'nine','variant'=>'draw'},player_count:5)
raise 'Valid eight-seat Holdem rejected' if game.validation_error({'deck'=>'nine','variant'=>'holdem'},player_count:8)
raise 'Impossible five-card exchange accepted' unless game.validation_error({'deck'=>'nine','variant'=>'draw','draw_five'=>true},player_count:4)
%w[draw holdem].each do |variant|
  env = GameRoomTest::PrivateSimulation.new_game(game:game,players:%w[Alice Bob Carol Dave],options:{'deck'=>'nine','variant'=>variant,'blind_interval'=>'never'},seed:992)
  30.times do
    break if env.finished?
    action = env.legal_actions.find { |item| item['action']=='bet' && %w[call check].include?(item['bet']) } || env.legal_actions.first
    raise 'Missing short-deck move' unless action
    raise 'Rejected short-deck move' unless env.step(action)==:ok
    cards = env.replay.state[:hands].values.flatten + env.replay.state[:deck] + env.replay.state[:community]
    raise 'Low card entered short-deck game' unless cards.all? { |card| %w[9 T J Q K A].include?(card[0]) }
  end
  raise 'Short-deck replay diverged' unless env.replay == game.replay(env.session,env.events,env.repository)
end
puts 'Poker short deck: 24 ranks, roster limits, both variants, complete deals and deterministic replay passed'
