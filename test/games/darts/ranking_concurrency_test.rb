require_relative '../../support/darts_rankings'
require 'timeout'

api = DartsRankingMemoryApi.new
store = store_for(api, 'Alice')
initial = ranking_row('seed', score:100, time:3000)
store.write_batch([result_operation(initial, publish:true)])

# B captures the old immutable snapshot. A then confirms its better record;
# B is released only afterwards, so a read/overwrite implementation loses A.
[api.personal_table, api.table_object].each do |table|
  entered, release = Queue.new, Queue.new
  paused = false
  stale_thread = nil
  table.after_select = lambda do |_query, rows|
    if Thread.current.equal?(stale_thread) && rows.empty? && !paused
      paused = true
      entered << true
      release.pop
    end
  end
  a = store_for(api, 'Alice')
  b = store_for(api, 'Alice')
  public_table = table.equal?(api.table_object)
  record_a = ranking_row(public_table ? 'public-a' : 'private-a', score:250, time:2500)
  record_b = ranking_row(public_table ? 'public-b' : 'private-b', score:200, time:2500)
  start = Queue.new
  stale_thread = Thread.new do
    start.pop
    records = single_record_set(record_b)
    b.instance_variable_set(:@limit, 1000)
    b.send(:update_records, table, records, nil, public:public_table)
  end
  # Do not let thread identity assignment race with its first select.
  stale_thread.report_on_exception = false
  start << true
  begin
    Timeout.timeout(5) { entered.pop }
    a.instance_variable_set(:@limit, 1000)
    a.send(:update_records, table, single_record_set(record_a), nil, public:public_table)
    release << true
    raise 'Concurrent writer did not complete' unless stale_thread.join(5)
    stale_thread.value
    records, snapshots = a.send(:read_records, table, nil, public:public_table)
    assert(records.dig('normal', 'triple').map { |row| row['score'] } == [250, 200, 100],
      "Concurrent #{public_table ? 'public' : 'private'} writer lost a confirmed record")
    assert(snapshots.length == 2, 'A stale writer removed a snapshot it never read')
    a.send(:update_records, table, single_record_set(record_b), nil, public:public_table)
    assert(table.rows.length == 1, 'The next write did not compact the concurrent snapshots')
  ensure
    release << true if stale_thread.alive?
    stale_thread.join(5)
    table.after_select = nil
  end
end

api.table_object.server_select_limit = 1
api.table_object.seed('Alice', single_record_set(ranking_row('public-b', score:200, time:2500)))
ranking = store.ranking(difficulty:'normal', category:'triple', fresh:true)
assert(ranking.map { |row| row['best_round_score'] } == [250, 200, 100],
  'Concurrent public snapshots created duplicate entries or skipped a short page')
api.table_object.lose_ack = true
operation = result_operation(ranking_row('lost-ack', score:290, time:2000), publish:true)
begin
  store.write_batch([operation])
  raise 'Lost insertion acknowledgement did not reach the caller'
rescue IOError
end
assert(store.write_batch([operation]) == 1, 'Lost insertion acknowledgement could not be reconciled')
assert(store.ranking(difficulty:'normal', category:'triple', fresh:true).map { |row| row['best_round_score'] } == [290, 250, 200],
  'Insertion retry lost or duplicated a record')
store.write_batch([{'kind'=>'darts_withdraw', 'match'=>'c' * 32}])
assert(api.table_object.rows.empty?, 'Withdrawal left a concurrent public snapshot')
assert(!api.personal_table.rows.empty?, 'Withdrawal deleted private records')
puts 'PASS Darts snapshot concurrency, safe compaction, short pages, lost ACK and withdrawal'
