require_relative '../support/ui'
require_relative '../support/log'
class Program
  def self.server_app(**_options); end
end
require_relative '../../__app'

def assert(value, message); raise message unless value; end
R = GameRoomSportsRankings::Result
assert(!R.respond_to?(:points), 'The retired sports ranking formula remains active')

Repo = Struct.new(:people) do
  def players_for(_session); people; end
  def actor_of(event, _session=nil); event['actor']; end
  def event_id(event); event['__id']; end
end
epoch = Time.utc(2026,10,24,12).to_i
make_session = ->(players,options) {
  {'__id'=>42,'__players'=>players,'__initial_players'=>players,'__insertion_user'=>'Owner',
    'options'=>JSON.generate(options),'__statistics'=>{'id'=>'bbc1a3de-71ef-4f91-b524-dd3070c405d9'}}
}
game = GameRoomGames::AxelPong.new
people = %w[Alice Bob]
session = make_session.call(people,{'target'=>'custom','custom_target'=>2})
events = 2.times.map { |index| {'__id'=>index+1,'actor'=>'Owner','__insertion_user'=>'Owner','__authority_user'=>'Owner',
  'action'=>'pong_point','value'=>"#{index}:0",'created_at'=>epoch+index} }
replay = game.replay(session,events,Repo.new(people))
assert(replay.finished?, 'Fixture did not finish the actual Pong game')
row = R.from_replay(game:game,session:session,replay:replay)
assert(R.parse(row)['sides']==[{'players'=>['Alice'],'goals'=>2},{'players'=>['Bob'],'goals'=>0}], 'Pong winner/goals export differs')
assert(R.from_replay(game:game,session:session,replay:game.replay(session,events.first(1),Repo.new(people))).nil?, 'Unfinished game was ranked')
assert(R.from_replay(game:game,session:session.merge('__aborted'=>true),replay:replay).nil?, 'Aborted game was ranked')
assert(R.from_replay(game:game,session:session.merge('__tournament_match'=>{}),replay:replay).nil?, 'Tournament game used the ordinary identity')

# Only the final lineup matters, not the original bot or analytics mode.
bot = GameRoomParticipants.bot_id(12,1)
changed = session.merge('__initial_players'=>['Alice',bot], '__seat_changes'=>[{'id'=>1,'players'=>people}],
  '__statistics'=>session['__statistics'].merge('mode'=>'bots'))
assert(R.from_replay(game:game,session:changed,replay:replay), 'An earlier bot excluded a human-only finish')
bot_session = make_session.call(['Alice',bot],{'target'=>'custom','custom_target'=>2})
bot_replay = game.replay(bot_session,events,Repo.new(['Alice',bot]))
assert(R.from_replay(game:game,session:bot_session,replay:bot_replay).nil?, 'A final bot was ranked')
late = session.merge('__players'=>%w[Alice Carol], '__seat_changes'=>[{'id'=>10,'players'=>%w[Alice Carol]}])
late_replay = game.replay(late,events,Repo.new(%w[Alice Carol]))
late_result = R.from_replay(game:game,session:late,replay:late_replay)
assert(late_result==row, "Replacement after the winning point changed a ranked result: #{[late_result,row].inspect}")

people = %w[Alice Bob Carol Dave]
session = make_session.call(people,game.with_team_assignment({'team_size'=>2,'target'=>'custom','custom_target'=>2},
  players: people, seats: [0,1,0,1]))
replay = game.replay(session,events,Repo.new(people))
double = R.parse(R.from_replay(game:game,session:session,replay:replay))
assert(double['sides']==[{'players'=>%w[Alice Carol],'goals'=>2},{'players'=>%w[Bob Dave],'goals'=>0}], 'Doubles split or duplicated team goals')
original_people=%w[Alice Bob Carol]+[bot]
old_options=game.with_team_assignment({'team_size'=>2,'target'=>'custom','custom_target'=>2},
  players:original_people,seats:[0,1,0,1])
replaced=make_session.call(people,old_options).merge('__initial_players'=>original_people,
  '__seat_changes'=>[{'id'=>2,'players'=>people}])
replaced_replay=game.replay(replaced,events,Repo.new(people))
assert(R.parse(R.from_replay(game:game,session:replaced,replay:replaced_replay))==double,
  'Doubles replacement retained obsolete team confirmation names')

# Use the real Audio Ball reducer: the score resets after each set, while
# ranking goals must include all accepted sets.
ball = GameRoomGames::AudioBall.new
people = %w[Alice Bob]
session = make_session.call(people,{'sets_to_win'=>2})
audio_events = [{'__id'=>1,'actor'=>'Owner','action'=>'audio_ball_start','value'=>'0','created_at'=>epoch}]
([0]*7+[1]*7+[0]*7).each_with_index do |side,index|
  audio_events << {'__id'=>index+2,'actor'=>'Owner','action'=>'audio_ball_point','value'=>"#{index}:#{side}",
    'created_at'=>epoch+10*(index+1)}
end
replay = ball.replay(session,audio_events,Repo.new(people))
assert(replay.finished? && replay.state[:sets]==[2,1], 'Audio Ball fixture did not finish three actual sets')
all_sets = R.parse(R.from_replay(game:ball,session:session,replay:replay))
assert(all_sets['sides'].map { |side| side['goals'] }==[14,7], 'Audio Ball ranked only the last set or counted sets as goals')

candidate = {'game_id'=>'axel_pong','game_options'=>{},'publication_ref'=>{'author'=>'Organizer','publication_key'=>'sample'},'schedule_id'=>'schedule'}
match = {'match_id'=>'fixture','leg'=>1}
receipt = {'summary'=>{'participants'=>%w[alice bob],'winners'=>['alice'],'draw'=>false,'scores'=>{'alice'=>11,'bob'=>0}}}
names = [{'account'=>'alice','username'=>'Alice'},{'account'=>'bob','username'=>'Bob'}]
forfeit = R.from_tournament(game:game,candidate:candidate,match:match,receipt:receipt,players:names,finished_at:epoch)
assert(R.parse(forfeit)['sides'].map { |side| side['goals'] }==[11,0], 'Forfeit lost its technical goals')
assert(R.from_tournament(game:game,candidate:candidate,match:match,receipt:{'summary'=>receipt['summary'].merge('resolution'=>'all_zero')},players:names,finished_at:epoch).nil?, 'All-zero settlement became a win')
ids = EltenGameRoom::GAME_REGISTRY.ids.select { |id| EltenGameRoom::GAME_REGISTRY.build(id).supports_leaderboards? }
assert(ids.sort == %w[darts krowa], 'Retired sports rankings remain available or the Darts/Krowa leaderboards disappeared')
GameRoomDartsRankings::Schema::TABLES.each do |name, schema|
  assert(EltenGameRoom::SERVER_TABLES.fetch(name) == schema, "Darts ranking schema missing from application declaration: #{name}")
end
statistics = EltenGameRoom::GAME_REGISTRY.ids.select { |id| EltenGameRoom::GAME_REGISTRY.build(id).supports_player_statistics? }
assert(statistics.sort == %w[audio_ball axel_pong], 'Personal statistics capabilities differ from the two sports games')
puts 'PASS sports statistics results: no ranking formula/capability, actual terminal reducers, full sets, final human roster, late replacement, doubles and technical forfeits'
