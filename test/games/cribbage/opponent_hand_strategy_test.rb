require_relative '../../../games/cribbage_support/cribbage_bot'
bot = GameRoomGames::CribbageBot
hand = [[4,:clubs],[7,:clubs],[8,:clubs],[6,:spades]]
seen = [[13,:hearts],[8,:spades]]
sequence = [13,8]
legal = hand.select { |card|GameRoomGames::CribbageScoring.pegging(sequence+[card.first]) }
before = Marshal.dump([hand,seen,sequence])
normal = bot.play(legal,sequence,hand:hand,seen:seen)
urgent = bot.play(legal,sequence,hand:hand,seen:seen,opponent_points_needed:2)
raise 'Imminent rival finish did not change the reply plan' unless normal==[8,:clubs] && urgent==[7,:clubs]
# Exact immediate-loss probability for a uniformly possible four-card hand.
pool = bot::DECK-(hand+seen)
risks = [normal,urgent].map do |card|
  wins = pool.count { |other|(GameRoomGames::CribbageScoring.pegging(sequence+[card.first,other.first]) || 0)>=2 }
  1-(0...4).reduce(1.0) { |p,i|p*(pool.size-wins-i).fdiv(pool.size-i) }
end
raise 'New urgency does not reduce actual finish exposure' unless risks[1]<risks[0]-0.07
raise 'Hypothetical hands changed live observations' unless Marshal.dump([hand,seen,sequence])==before
raise 'No-card opponent invented a reply' unless legal.include?(bot.play(legal,sequence,hand:hand,seen:seen,opponent_count:0))
puts 'PASS Cribbage hand-conditioned replies, urgent 121 prevention, exact immediate loss reduction and nonmutation'
