require_relative '../../support/new_games_fixture'
model = GameRoomPokerOpponents
entries = []
80.times do |hand|
  street,pressure,action = hand<40 ? [0,10,'fold'] : [3,10,hand<60 ? 'call' : 'fold']
  pressure = 150 if hand>=60
  data = {'call'=>pressure,'pot'=>100,'raise_by'=>0,'street'=>street,'hand'=>hand,'action'=>action}
  entries << GameRoomGames::HistoryEntry.new(key:hand.to_s,event_id:hand,actor:'Bob',field:'poker_bet',value:data)
end
before = Marshal.dump(entries)
profiles = model.profiles(entries)
pre = model.profile(profiles,'BOB',street:0,pressure:0.1)
small = model.profile(profiles,'Bob',street:3,pressure:0.1)
large = model.profile(profiles,'Bob',street:3,pressure:0.6)
assert(pre[:fold]>small[:fold], 'Preflop folds leaked into river calls without contextual evidence')
assert(large[:fold]>small[:fold], 'Responses to large and small relative bets were merged')
assert(model.profile(profiles,'Bob',street:2)==model.profile(profiles,'Bob'), 'Unseen street invented confidence')
assert(model.profile(profiles,'New',street:3,pressure:0.6)[:observations].zero?, 'An unseen player inherited evidence')
assert(Marshal.dump(entries)==before, 'Context learning rewrote public history')
puts 'PASS poker street/relative-size response evidence, shrinkage, unseen context and public history nonmutation'
