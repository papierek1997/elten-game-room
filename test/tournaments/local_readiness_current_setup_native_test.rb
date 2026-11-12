ENV['ELTEN_TEST_NATIVE_CONTROLS'] = '1'
require_relative '../support/temporary_directory'
require_relative '../support/tournament_native'
require_relative '../support/tournament_entry_context'
require_relative '../support/tournament_local_hub'
require_relative '../support/tournament_window_fields'
require File.join(EltenTestHost.root, 'src/ui/controls/static')
Object.const_set(:Static, EltenAPI::Controls.const_get(:Static)) unless Object.const_defined?(:Static)
require_relative '../../lib/tournaments/local_test_hub'
include GameRoomTest::Assertions
T = GameRoomTournaments
H = TournamentLocalHubTest
# The real task wait has no desktop in this isolated fixture. As in the
# maintained native hub test, only its PassiveUI wait yields; forms stay native.
module EltenAPI
  def loop_update
    Thread.pass
  end
end
GameRoomLocalization.boot(settings: {'interface_language' => 'en', 'known_languages' => ['en']})

GameRoomTest::TemporaryDirectory.create('current-k03-') do |directory|
program = TournamentEntryContextTest::Program.new(directory)
now, alerts = 1_800_000_000, []
hub = T::LocalTestHub.new(program: program, registry: GameRoomGames::CATALOG,
  user: -> {'RealOwner'}, alert: ->(message) {alerts << message},
  confirm: ->(*) {raise 'Unexpected confirmation'}, clock: -> {now})
driver = TournamentNativeDriver.new
observed = nil
complete = lambda do |form|
  screen = hub.instance_variable_get(:@match_entry)
  work = screen.instance_variable_get(:@readiness_work)
  wait_background_work(work) if work && work.busy?
  form.update
end
driver.step('Local tournament tests', [13]) do |form|
  form.index = form.fields.index(H.button(form, 'Create and publish tournament'))
end
driver.step('Game', [13]) do |form|
  form.fields.first.index = GameRoomGames::CATALOG.ids.index('tic_tac_toe')
end
driver.step(nil, [13]) { |form| form.index = form.fields.index(form.accept_button) }
driver.step('Tournament name', [13]) do |form|
  H.field(form, 'Tournament name').set_text('Current creator to K03')
  form.index = form.fields.index(H.button(form, 'Dates and playing hours'))
end
driver.step('Dates and playing hours', [13]) do |form|
  closing = form.fields.find { |field| field.is_a?(CheckBox) && field.label == 'Schedule the close of registration' }
  closing.checked = true
  closing.trigger(:change)
  form.index = form.fields.index(form.accept_button)
end
driver.step('Tournament name', [13]) { |form| form.index = form.fields.index(form.accept_button) }
driver.step('Local tournament tests', [13]) do |form|
  assert_equal([], alerts, 'Current native creation raised an alert')
  workspace = hub.instance_variable_get(:@workspace)
  publication = workspace.load.fetch('announcements').fetch(0)
  assert_equal(2, publication['schema_version'])
  bob = T::LocalWorkspace.new(program: program, registry: GameRoomGames::CATALOG,
    user: -> {'RealOwner'}, actor: 'Bob', alert: ->(message) {alerts << message}, clock: -> {now})
  assert_equal('confirmed', bob.join(publication['__id'])['status'])
  now = publication.fetch('registration_closes_at') + 1
  H.button(form, 'Advanced local test tools').press
  form.index = form.fields.index(H.button(form, 'My matches — readiness and coordination'))
end
driver.step('My tournaments') do |form|
  screen = hub.instance_variable_get(:@match_entry)
  H.button(form, 'Check status').press
  complete.call(form)
  assert_equal(:candidate, screen.controller.reason)
  assert_equal(1, screen.controller.view.fetch(:matches).size)
  H.button(form, 'Prepare local test plan').press
  complete.call(form)
end
driver.step('Local test plan', [13]) do |form|
  form.index = form.fields.index(H.button(form, 'Accept local test plan'))
end
driver.step('My tournaments', [27]) do |form|
  complete.call(form)
  screen = hub.instance_variable_get(:@match_entry)
  state = screen.instance_variable_get(:@readiness_state)
  candidate = screen.controller.view.fetch(:candidate)
  candidate = candidate.to_h if candidate.respond_to?(:to_h)
  observed = {candidate_class: screen.controller.view[:candidate].class.name,
    candidate_fields: candidate.keys.sort, starts_at: candidate['starts_at'],
    registration_opens_at: candidate['registration_opens_at'],
    registration_closes_at: candidate['registration_closes_at'],
    roster: candidate['roster'], state: state[:state], reason: state[:reason],
    displayed_status: H.field(form, 'Readiness and coordination').text,
    accepted_local_plans: Dir.glob('**/sandbox-k03.json', base: directory).sum do |path|
      JSON.parse(File.binread(File.join(directory, path))).fetch('plans').length
    end}
end
driver.step('Local tournament tests', [27])
begin
  hub.run
  driver.finish
  assert_equal(0, program.managed_resources.size)
  assert_equal(0, program.class.app_runtime.managed_resources.size)
ensure
  program.finalize
  program.class.app_runtime.close
end
assert_equal(0, observed.fetch(:starts_at))
assert_equal(:confirmed, observed.fetch(:state))
assert(observed && observed[:state] != :blocked && observed[:accepted_local_plans] == 1,
  'Current native creation and native explicit local-plan acceptance was refused')
end
puts 'PASS current native tournament setup, optional dates, real second participant, complete local-plan acceptance and closed resources'
