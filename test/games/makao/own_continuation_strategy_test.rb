require_relative '../../support/makao_positions'
game = GameRoomGames::Makao.new
state = playing_makao_state(game,%w[Alice Bob],{'profile'=>'simple'},current:'Alice',
  hands:{'Alice'=>%w[7H 7D 7C 9C],'Bob'=>%w[6S 8S]},top:'9H')
state[:skip_turns]['Bob'] = 2
replay = makao_replay(state)
before = Marshal.dump(state)
actions = game.legal_actions(replay,'Alice')
proved = game.send(:bot_own_finishes,replay,'Alice',actions)
raise 'Known skipped turns lost a proven own finishing packet' unless proved.any? { |a|JSON.parse(a['cards'])==%w[7H 7D 7C] }
raise 'Disconnected packet was marked a certain win' if proved.any? { |a|JSON.parse(a['cards'])==%w[7H 7C 7D] }
choice = game.bot_strategy.choose(actions:actions,actor:'Alice',game:game,replay:replay,random_source:GameRoomRandom::SeededSource.new(1))
raise 'Chosen proven move rejected' unless game.action_for(choice,replay,'Alice',context:context_for).first==:ok
raise 'Planning changed live hands or skips' unless Marshal.dump(state)==before
state[:skip_turns]['Bob']=0
raise 'An ordinary rival turn was silently skipped' unless game.send(:bot_own_finishes,makao_replay(state),'Alice',actions).empty?
puts 'PASS Makao known own-turn finish, packet bridge, ordinary validation, nonmutation and stopping at unknown defence'
