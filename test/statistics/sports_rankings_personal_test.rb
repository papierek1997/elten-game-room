require 'date'
require_relative '../../lib/sports_rankings/personal'
def assert(value,message); raise message unless value; end

P = GameRoomSportsRankings::Personal
today=Date.new(2026,10,27)
match=->(winner,loser,date) {
  {'day_key'=>date.strftime('%Y%m%d').to_i,'winner'=>0,
    'sides'=>[{'players'=>winner,'goals'=>11},{'players'=>loser,'goals'=>3}]}
}
matches=[match.call(['ALICE'],['Tomciolog'],today),match.call(['Tomciolog'],['Alice'],today-6),
  match.call(['Alice'],['Bob'],today-7),match.call(['Alice'],['bob'],today-29),match.call(['Zed'],['Alice'],today-30),
  match.call(['Alice'],['Zed'],(today<<12)+1),match.call(['Alice'],['Zed'],today<<12),match.call(['Bob'],['Zed'],today)]
rows=P.summary(matches,user:'alice',today:today)
assert(rows.map { |r| r['players'] }==[['alice'],['Bob'],['Tomciolog'],['Zed']],'Own entry must come first, then opponents alphabetically')
counts=->(row) { P::PERIODS.map { |p| row['periods'][p].values_at('won','lost') } }
# 7 days and 30 days include today; half-year and year are calendar months; other players' matches do not count.
assert(counts.call(rows[0])==[[5,2],[1,1],[3,1],[3,2],[4,2]],'Own period counts differ')
assert(counts.call(rows[2])==[[1,1]]*5,'Head-to-head counts differ')
assert(counts.call(rows[1])==[[2,0],[0,0],[2,0],[2,0],[2,0]] && counts.call(rows[3])==[[2,1],[0,0],[0,0],[0,1],[1,1]],'Older head-to-head periods differ')
assert(rows[0]['own'] && rows[1..].none? { |r| r['own'] },'Own entry is not marked')

# Doubles opponents are pairs; partners are not opponents.
pairs=P.summary([match.call(%w[Alice Carol],%w[Bob Dave],today),match.call(%w[dave bob],%w[Alice Eve],today)],user:'Alice',today:today)
assert(pairs.map { |r| r['players'] }==[['Alice'],%w[Bob Dave]] && pairs[1]['periods']['week']=={'won'=>1,'lost'=>1},'Doubles opponents are not pairs')
assert(P.summary([],user:'Alice',today:today).size==1,'Viewer without matches is missing')
puts 'PASS sports personal statistics: own counts, alphabetical head-to-head opponents, inclusive periods and doubles pairs'
