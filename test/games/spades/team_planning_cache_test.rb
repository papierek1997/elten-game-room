require_relative '../../support/binary_rule_dictionary'

game = GameRoomGames::Spades.new
calls = 0
original = game.method(:team_assignment)
game.define_singleton_method(:team_assignment) { |*args,**kwargs| calls+=1; original.call(*args,**kwargs) }
state = {players:%w[A B C D], options:game.normalize_options('team_size'=>2)}
first = game.send(:bot_team_assignment,state)
100.times { raise 'Cached assignment changed' unless game.send(:bot_team_assignment,state).equal?(first) }
raise 'Public assignment rebuilt during hypothetical decisions' unless calls==1
state[:options]['team_size']=0
raise 'In-place option change retained team' unless game.send(:bot_team_assignment,state).nil?
raise 'Missing nil-cache invalidation' unless calls==2
100.times { game.send(:bot_team_assignment,state) }
raise 'Solo assignment misses cache' unless calls==2
state[:options]['team_size']=2
state[:players].rotate!
again = game.send(:bot_team_assignment,state)
expected = original.call(state[:options],players:state[:players])
raise 'Roster reorder changed semantic assignment' unless state[:players].all? { |p|again.team_index_for(p)==expected.team_index_for(p) }
raise 'Caller options retained by mutable cache key' unless calls==3
puts 'PASS Spades team cache: bounded one entry, ordinary/solo and in-place roster/options invalidation'
