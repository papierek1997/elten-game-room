require_relative '../support/settings_widget'

fake_inbox = Class.new do
  attr_accessor :pending
  attr_reader :ticks, :revocation_drains

  def initialize
    @pending = false
    @ticks = 0
    @revocation_drains = 0
  end

  def work_pending?; @pending; end
  def tick; @ticks += 1; []; end
  def take_revoked; @revocation_drains += 1; []; end
end

old_start = EltenGameRoom.instance_variable_get(:@tournament_start_inbox)
old_events = EltenGameRoom.instance_variable_get(:@tournament_event_inboxes)
begin
  start = fake_inbox.new
  events = 4.times.to_h { |index| [index, fake_inbox.new] }
  EltenGameRoom.instance_variable_set(:@tournament_start_inbox, start)
  EltenGameRoom.instance_variable_set(:@tournament_event_inboxes, events)

  EltenGameRoom.tournament_starts_tick
  assert([start, *events.values].all? { |inbox| inbox.ticks == 0 && inbox.revocation_drains == 0 },
    'Idle tournament inboxes were drained by the extension tick')

  events.fetch(2).pending = true
  EltenGameRoom.tournament_starts_tick
  assert([start, *events.values].all? { |inbox| inbox.ticks == 1 && inbox.revocation_drains == 1 },
    'Pending tournament work did not wake the ordinary one-second drain')
ensure
  EltenGameRoom.instance_variable_set(:@tournament_start_inbox, old_start)
  EltenGameRoom.instance_variable_set(:@tournament_event_inboxes, old_events)
end

puts 'PASS tournament idle tick: empty inboxes skip allocation work and pending work keeps the ordinary drain'
