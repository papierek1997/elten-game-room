require 'date'
require 'monitor'
require_relative '../support/statistics_tables'
require_relative '../../lib/sports_rankings/service'
module EltenLink
  class Client; end
end
def assert(value,message); raise message unless value; end

class SportsMemoryTable < StatisticsMemoryTable
  def select(where: {}, **options)
    raise 'Native server rejects ambiguous where operators' if where.values.any? { |value| value.is_a?(Hash) && value.size>1 }
    super(where:where,**options)
  end
end
class SportsMemoryApi
  attr_reader :table_object, :schema_calls
  def initialize
    @table_object, @schema_calls = SportsMemoryTable.new, 0
  end
  def schema(*)
    @schema_calls += 1
    definitions = Marshal.load(Marshal.dump(GameRoomSportsRankings::Schema::TABLES))
    definitions.each_value do |table|
      table['permissions']=table['permissions'].to_h { |name| [name,true] }
      table['unique_per_user']=false
    end
    {'data'=>{'server'=>{'tables'=>definitions}}}
  end
  def table(*); @table_object; end
end
class SportsMemoryStorage
  attr_reader :data, :writes
  def initialize; @data, @writes, @lock = {}, 0, Monitor.new; end
  def read_json(path,default:nil); Marshal.load(Marshal.dump(@data.fetch(path,default))); end
  def update_json(path,default:nil)
    @lock.synchronize do
      @writes += 1
      value=read_json(path,default:default)
      yield value
      @data[path]=Marshal.load(Marshal.dump(value))
    end
  end
end
R = GameRoomSportsRankings::Result
epoch=Time.utc(2026,10,24,12).to_i
build=->(key,goals=[11,0],people=[['Alice'],['Bob']],date=epoch) {
  R.build(identity:key,game:'axel_pong',finished_at:date,
    sides:people.each_with_index.map { |names,i| {'players'=>names,'goals'=>goals[i]} },winner:0)
}
api=SportsMemoryApi.new
store=GameRoomSportsRankings::Store.new(app_uuid:'test',user:'Alice',api:api,client:Object.new,current_user:-> {'ALICE'})
row=build.call('one')
assert(store.write_batch([row])==1,'First report was not acknowledged')
assert(store.write_batch([row])==1 && api.table_object.rows.size==1,'Retry duplicated the same report')
assert(store.write_batch([row.merge('finished_at'=>epoch+1)])==1 && api.table_object.rows.size==1,'Server-time reconciliation rejected the same sporting outcome')
api.table_object.insert(row) # Two clients can race; canonical first ID wins.
store.write_batch([build.call('old',[2,0],[['Alice'],['Bob']],epoch-40*86400)])
report=store.report(game:'axel_pong',mode:'singles',from_day:20261018,to_day:20261024)
assert(report.map { |r| r['won'] }==[1,0] && report.map { |r|r['lost']}==[0,1],'Duplicate or out-of-period match counted')
assert(report.first.values_at('scored','conceded')==[11,0],'Recorded goals changed')
assert(report.all? { |value| value.keys.sort == %w[conceded lost scored user won] }, 'Sports reports still calculate points or places')
api.table_object.server_select_limit=1
store.write_batch([build.call('two',[2,0])])
report=store.report(game:'axel_pong',mode:'singles',from_day:nil,to_day:20261024)
assert(report.first['won']==3,'A short nonempty server page stopped pagination')
assert(report.first['scored']==15,'Statistics changed the unweighted totals of short and long matches')
store.write_batch([build.call('doubles',[11,0],[%w[Alice Carol],%w[Bob Dave]])])
report=store.report(game:'axel_pong',mode:'doubles',from_day:nil,to_day:20261024)
assert(report.size==4 && report.select { |r|r['won']==1 }.all? { |r|r['scored']==11 },'Team goals were divided among members')
assert(report.map { |r| r['user'] }==%w[Alice Bob Carol Dave], 'Unranked statistics are not ordered by username')
assert(report.none? { |r| r.key?('place') || r.key?('points') }, 'Statistics still assign ranking places or points')

# Short aggregate replies must also be completed, independently of data pages.
api.table_object.server_select_limit=1000
api.table_object.after_select=->(query,rows) { rows.slice!(1..-1) if query[:group_by] && rows.size>1 }
report=store.report(game:'axel_pong',mode:'singles',from_day:nil,to_day:20261024,fresh:true)
assert(report.first['won']==3,'A short canonical group page lost ranked matches')
api.table_object.after_select=nil
calls=api.table_object.queries.size
store.report(game:'axel_pong',mode:'singles',from_day:nil,to_day:20261024)
assert(api.table_object.queries.size==calls,'The bounded report cache did not reuse its snapshot')
store.report(game:'axel_pong',mode:'singles',from_day:nil,to_day:20261024,fresh:true)
assert(api.table_object.queries.size>calls,'Explicit Refresh reused a cached snapshot')

# Head-to-head reads the same canonical history; the report keeps its own cache entry.
today=Date.new(2026,10,24)
mine=store.personal(game:'axel_pong',mode:'singles',today:today)
assert(mine.map { |r| r['players'] }==[['Alice'],['Bob']] && mine[1]['periods']['all']=={'won'=>3,'lost'=>0} &&
  mine[1]['periods']['month']=={'won'=>2,'lost'=>0},"Head-to-head counted duplicates or the wrong period: #{mine.inspect}")
bob=store.personal(game:'axel_pong',mode:'singles',today:today,player:'bob')
assert(bob.map { |r| r['players'] }==[['bob'],['Alice']] && bob[1]['periods']['all']=={'won'=>0,'lost'=>3},'A chosen player did not get their own opponents')
pair=store.personal(game:'axel_pong',mode:'doubles',today:today)
assert(pair.map { |r| r['players'] }==[['Alice'],%w[Bob Dave]],'Doubles head-to-head did not use the opposing pair')
calls=api.table_object.queries.size
store.report(game:'axel_pong',mode:'singles',from_day:nil,to_day:20261024)
store.personal(game:'axel_pong',mode:'singles',today:today)
assert(api.table_object.queries.size==calls,'Alternating report and head-to-head reads evicted each other')

batch=(1..30).map { |index| build.call("batch-#{index}") }
assert(store.write_batch(batch)==25,'A sports upload exceeded the bounded pass')
api.table_object.lose_ack=true
lost=build.call('lost-ack')
begin
  store.write_batch([lost])
  raise 'Uncertain write was incorrectly acknowledged'
rescue IOError
end
assert(store.write_batch([lost])==1 && api.table_object.rows.count { |r|r['match_key']==lost['match_key'] }==1,'Uncertain retry duplicated a match')

account='Alice'
storage=SportsMemoryStorage.new
queued=[]
writer=Object.new
writer.define_singleton_method(:write_batch) { |values,**_| queued.concat(values); values.size }
program=Object.new
program.define_singleton_method(:server_app_uuid) { 'test' }
service=GameRoomSportsRankings::Service.new(program:program,user:'Alice',storage:storage,store:writer,current_user:-> {account})
assert(service.send(:record,row),'Could not stage completed match')
assert(storage.writes.zero? && queued.empty?,'Enqueue performed disk or network I/O')
assert(!service.send(:record,row),'Repeated completion was enqueued twice')
assert(!service.send(:record,row.merge('finished_at'=>epoch+1)),'Canonical server time duplicated or blocked the local result')
service.flush
assert(storage.writes>0 && queued.size==1,'Background flush did not persist and upload')
assert(storage.data.key?('sports-rankings-pending.json') && !storage.data.key?('statistics-pending.json'),'Sports results collided with existing statistics')
reopened=GameRoomSportsRankings::Service.new(program:program,user:'Alice',storage:storage,store:writer,current_user:-> {account})
reopened.send(:record,row)
reopened.flush
assert(queued.size==1,'Cold restart lost acknowledgement deduplication')
account='Bob'
begin
  service.send(:record,build.call('wrong-account'))
  raise 'Account change allowed another upload'
rescue GameRoomStatistics::Unavailable
  assert(queued.size==1,'Account change uploaded a result')
end
puts 'PASS sports persistence: immutable receipts, racing/duplicate reports, period scope, short pages, teams, durable background queue and account isolation'
