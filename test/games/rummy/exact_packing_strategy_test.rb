require_relative '../../../lib/rummy_planner'
planner = GameRoomRummyPlanner
hand = %w[6D1 5S1 X11 5D1 3H1 X01 4H1 9H1 3D0 3S0 6S1 4H0 4S0 4C0]
before = Marshal.dump(hand)
best = planner.plans(hand).first
raise 'Small exact pack still loses the twelve-card layout' unless best[:cards].size==12 && planner.utility(best,[])==1260
raise 'Physical card reused' unless best[:cards].uniq==best[:cards]
raise 'Invalid production meld' unless best[:groups].all? { |g|GameRoomRummyRules.validate(g) }
raise 'Input hand mutated' unless before==Marshal.dump(hand)
raise 'Unreachable first-meld threshold accepted' unless planner.plans(hand,minimum:1000).empty?
constrained = planner.plans(hand,minimum:55,debts:['X','X']).first
raise 'Threshold/debt state dropped from exact search' unless constrained && constrained[:points]>=55 && planner.repaid(constrained[:cards],['X','X'])==2
raise 'Exhausted exact search publishes partial result' unless planner.exact_plan(hand,[],0,[],limit:0).nil?
puts 'PASS Rummy: twelve-card exact pack, physical legality, debt/entry constraints and bounded fallback'
