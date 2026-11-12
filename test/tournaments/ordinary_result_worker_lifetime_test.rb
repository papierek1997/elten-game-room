require_relative '../support/tournament_forfeit_native'
require 'timeout'

# Use the actual native-contract match and normal result collector. Only gates
# observe its thread boundary; they do not fabricate a result or an ACK.
TournamentForfeitNative.with_fixture do |fixture|
  fixture.start
  h = fixture.h
  services = fixture.services.values
  assert(services.none? { |service| service.instance_variable_get(:@thread)&.alive? },
    'Opening a match retained an idle result worker before any result existed')
  service = fixture.services.fetch('Alice')
  collected, resume = Queue.new, Queue.new
  collect = service.method(:collect)
  service.define_singleton_method(:collect) do |row, pending: nil|
    collected << Thread.current
    resume.pop
    collect.call(row, pending: pending)
  end
  12.times do
    replay = h.replay('Alice')
    break if replay.finished?
    h.submit(replay.current_player, h.game.legal_actions(replay, replay.current_player).first)
  end
  replay = h.replay('Alice')
  assert(replay.finished?, 'The native-contract match did not finish')
  events = h.events('Alice')
  assert(service.observe(h.table, h.session, replay, events), 'Terminal result was not queued')
  worker = Timeout.timeout(3) { collected.pop }
  assert(worker.alive?, 'The collector did not enter its finite work boundary')
  duplicates = Array.new(8) { Thread.new { service.observe(h.table, h.session, replay, events) } }
  duplicates.each(&:value)
  assert(service.instance_variable_get(:@jobs).empty?, 'Repeated terminal observations queued duplicate results')
  resume << true
  assert(worker.join(3), 'Result worker remained blocked after completing its only job')
  assert(service.instance_variable_get(:@thread).nil?, 'Completed worker retained an active worker slot')
  assert(collected.empty?, 'The same sporting result was collected again')
  assert(fixture.services.fetch('Bob').result_view.fetch('completed'), 'Finite worker lost the canonical tournament result')
  assert(service.instance_variable_get(:@result_jobs).empty?, 'Completed result retained a retry job')
  assert(service.take_error.nil?, 'Finite result collection produced an error')
ensure
  resume << true if defined?(resume) && resume
end
puts 'PASS ordinary tournament result worker: no pre-result thread, native match/result, concurrent deduplication, idle exit and canonical result'
