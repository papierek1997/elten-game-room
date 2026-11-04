require_relative '../../lib/tournaments/tournament_finish_summary'

def assert(value,message); raise message unless value; end
T=GameRoomTournaments
table=->(people) { people.each_with_index.map { |unit,index| {'unit'=>unit,'place'=>index+1} } }
current={'format'=>'knockout','knockout'=>{'round'=>3}}
results={'completed'=>true,'champion'=>'a','standings'=>table.call(%w[a b])}
history=[
  {'candidate'=>{'format'=>'groups_knockout'},'view'=>{'standings'=>table.call(%w[a b c d e f g h])}},
  {'candidate'=>{'format'=>'knockout','knockout'=>{'round'=>2}},'view'=>{'standings'=>table.call(%w[a b c d])}}
]
before=Marshal.dump([current,results,history])
summary=T::TournamentFinishSummary.build(candidate:current,results:results,history:history,usernames:{'a'=>'Alpha'})
assert(summary['places']=={'a'=>1,'b'=>2,'c'=>3,'d'=>3,'e'=>5,'f'=>5,'g'=>5,'h'=>5},'Elimination stages invented an ordering within a cohort')
assert(summary['winners']==['Alpha'] && summary['team_mode']==false,'Winner lost registered name or singles mode')
assert(Marshal.dump([current,results,history])==before,'Notice summary mutated sporting results')
assert(!summary['places'].key?('organizer'),'Non-playing organizer received a finishing place')

round_robin={'format'=>'round_robin'}
ties={'completed'=>true,'standings'=>[{'unit'=>'a','place'=>1},{'unit'=>'b','place'=>1},{'unit'=>'c','place'=>3}]}
summary=T::TournamentFinishSummary.build(candidate:round_robin,results:ties,history:[],usernames:{})
assert(summary['places']=={'a'=>1,'b'=>1,'c'=>3} && summary['winners']==%w[a b],'Published equal places were split or renumbered')

membership={'units'=>[
  {'unit_id'=>'team0','accounts'=>%w[a b]}, {'unit_id'=>'team1','accounts'=>%w[c d]},
  {'unit_id'=>'team2','accounts'=>%w[e f]}, {'unit_id'=>'team3','accounts'=>%w[g h]}]}
history=[{'candidate'=>{'format'=>'knockout','membership'=>membership},'view'=>{'standings'=>table.call(%w[team0 team1 team2 team3])}}]
current={'format'=>'knockout','membership'=>{'units'=>membership['units'].values_at(0,2)}}
results={'completed'=>true,'champion'=>'team2','standings'=>table.call(%w[team2 team0])}
summary=T::TournamentFinishSummary.build(candidate:current,results:results,history:history,usernames:{'e'=>'Ewa','f'=>'Franek'})
assert(summary['places']=={'e'=>1,'f'=>1,'a'=>2,'b'=>2,'c'=>3,'d'=>3,'g'=>3,'h'=>3},'A team was counted as two sporting units')
assert(summary['winners']==['Ewa + Franek'] && summary['team_mode'],'Winning team lost its players')
summary=T::TournamentFinishSummary.build(candidate:current,results:results.merge('champion'=>nil),history:history,usernames:{})
assert(summary['winners'].empty? && summary['places'].empty?,'Void final fabricated a winner or a finishing place')
puts 'PASS tournament finish summary: ties, all elimination stages, groups, whole teams, names, non-playing organizer and void final'
