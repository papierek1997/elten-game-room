require_relative '../support/table_voice_controller'
require_relative '../../lib/table_voice_membership'

# Native create has already joined the creator, but its :update callback may
# not yet have reached the form. This is a local Conference device contract;
# it does not open a Windows window, change keys or contact a real account.
class UnpublishedCreatedConference < LocalConferenceDevice
  def initialize
    super
    self.auto_connect = false
  end

  def create(*arguments)
    id = super
    person = Struct.new(:name).new(Session.name)
    self.channel = Struct.new(:id, :name, :users).new(id, arguments.first, [person])
    id
  end
end

checks = []
[false, true].each do |switch_away|
  harness = NativeRoomHarness.new(users: %w[Alice Bob])
  host = harness.transports.fetch('Alice')
  notices = []
  program = voice_program(notices)
  conference = UnpublishedCreatedConference.new
  driver = TournamentControlCallbacks.new
  creation_step(driver)
  driver.step('Voice conversation') do |form|
    assert_equal('Connecting to the voice conversation...', form.fields.first.text)
    assert_equal(246, conference.channel.id)
    assert_equal('Table conference', conference.channel.name)
    if switch_away
      conference.channel = Struct.new(:id, :name).new(246, 'Unrelated reused-ID conference')
    end
    form.fields.grep(Button).find { |button| button.label == 'Back' }.press
  end
  driver.step('Voice conversation') do |form|
    assert_equal(['Back'], form.fields.grep(Button).map(&:label))
    form.fields.grep(Button).last.press
  end
  harness.as('Alice') do
    GameRoomTableVoiceScreen.new(program: program, transport: host,
      table: harness.table, conference: conference).run
  end
  driver.finish
  voice = harness.as('Bob') { harness.transports.fetch('Bob').table_voice(harness.table, force: true) }
  checks << {
    case: switch_away ? 'unrelated_reused_id' : 'unpublished_creator',
    claim_cleared: voice['status'] == 'none',
    hooks_removed: conference.hooks.empty?,
    leaves: conference.leaves,
    channel_id: conference.channel&.id,
    channel_name: conference.channel.respond_to?(:name) ? conference.channel.name : nil,
    cleanup_correct: switch_away ?
      (conference.leaves.zero? && conference.channel.name == 'Unrelated reused-ID conference') :
      (conference.leaves == 1 && conference.channel.id == 0)
  }
end

puts JSON.generate(checks)
assert(checks.all? { |row| row[:claim_cleared] && row[:hooks_removed] && row[:cleanup_correct] },
  'Unpublished Conference creation leaked membership or disconnected an unrelated channel')
puts 'PASS cancelled unpublished native creation releases only its own channel, preserving unrelated reused IDs'

# A failed leave or a still-delayed native view must not lose the exact local
# identity. Ordinary table departure, not a retained callback, owns recovery.
[:failed_leave, :delayed_view].each do |mode|
  harness = NativeRoomHarness.new(users: %w[Alice Bob])
  notices = []
  program = voice_program(notices)
  conference = UnpublishedCreatedConference.new
  membership = GameRoomTableVoiceMembership.new(conference: conference)
  program.define_singleton_method(:remember_table_voice) { |table| membership.remember(table) }
  conference.leave_success = false if mode == :failed_leave
  driver = TournamentControlCallbacks.new
  creation_step(driver)
  driver.step('Voice conversation') do |form|
    conference.channel = Struct.new(:id).new(0) if mode == :delayed_view
    form.fields.grep(Button).last.press
  end
  driver.step('Voice conversation') { |form| form.fields.grep(Button).last.press }
  harness.as('Alice') do
    GameRoomTableVoiceScreen.new(program: program, transport: harness.transports.fetch('Alice'),
      table: harness.table, conference: conference).run
    driver.finish
    conference.leave_success = true
    conference.complete_creation if mode == :delayed_view
    assert(membership.connected?(harness.table), "Lost #{mode} local membership")
    assert(membership.depart(harness.table), "Could not recover #{mode} membership")
    assert_equal(0, conference.channel.id)
    assert(conference.hooks.empty?, "Retained #{mode} update hook")
  end
end
puts 'PASS unpublished membership recovery survives failed leave and delayed native view'

# A rejected publication can return another ready invitation. That is not
# confirmation of the channel we just allocated, even if its fields match.
[nil, false, true].each do |accepted|
  harness = NativeRoomHarness.new(users: %w[Alice Bob])
  host = harness.transports.fetch('Alice')
  notices, remembered = [], []
  program = voice_program(notices)
  program.define_singleton_method(:remember_table_voice) { |table| remembered << table.fetch('voice') }
  conference = LocalConferenceDevice.new
  driver = TournamentControlCallbacks.new
  creation_step(driver)
  original_change = host.method(:change_table_voice)
  host.define_singleton_method(:change_table_voice) do |table, data, **arguments|
    response = original_change.call(table, data, **arguments)
    next response unless data['operation'] == 'publish'
    accepted.nil? ? nil : response.merge(accepted: accepted)
  end
  harness.as('Alice') do
    result = GameRoomTableVoiceScreen.new(program: program, transport: host,
      table: harness.table, conference: conference).run
    driver.finish
    assert_equal(accepted == true, result == true)
    assert_equal(accepted == true ? 0 : 1, conference.leaves)
    assert_equal(accepted == true ? 1 : 0, remembered.size)
    assert(conference.hooks.empty?, 'Retained publication update hook')
  end
end
puts 'PASS only accepted exact publication retains the created native conference'
