# frozen_string_literal: true
ENV['ELTEN_TEST_NATIVE_CONTROLS'] = '1'
require_relative '../support/binary_rules_load'
require_relative '../support/tournament_control_callbacks'
require_relative '../support/tournament_public_ui'
require_relative '../../lib/tournaments/public_screen'
require_relative '../../lib/tournaments/tournament_event_notice'
include GameRoomTest::Assertions

class PartnershipEntryCallbacks < TournamentControlCallbacks
  attr_reader :views

  def initialize
    super
    @views = []
  end

  def tick(form)
    if form.is_a?(GameRoomUI::Form) && form.instance_variable_get(:@wait) == true && !@executing[form]
      step(form.fields.first.header) do |current|
        assert(current.is_a?(EltenAPI::Controls::Form), 'The entry must use the actual native form')
        @views << {header: current.fields.first.header,
          options: current.fields.grep(ListBox).flat_map(&:options)}
        current.cancel_button.press
      end
    end
    super
  end
end

T = GameRoomTournaments
U = TournamentPublicUI
GameRoomLocalization.boot(settings: {'interface_language'=>'en', 'known_languages'=>['en']})
now = 300
options = GameRoomGames::CATALOG.build('mille_bornes').default_options.merge('team_count'=>2)

make_snapshot = lambda do |start|
  row = U.publication(11, game: 'mille_bornes', options: options,
    **{'players_per_match'=>4, 'participant_limit'=>4, 'windows'=>[], 'starts_at'=>start, 'deadline_at'=>0})
  joins = %w[Alpha Beta Gamma Delta].each_with_index.map do |name, index|
    U.registration(100+index, user: name, time: 150)
  end
  initial = T::RegistrationProjection.build(announcements: [row], registrations: joins,
    registry: GameRoomGames::CATALOG, complete: true)
  draw = U.registration(110, user: row.fetch('__insertion_user'), time: 251).merge(
    'kind'=>'pair_draw', 'account'=>row.fetch('__insertion_user').downcase, 'partner'=>nil,
    'pairing_generation'=>initial.partnership_state(11).fetch('draw_generation'),
    'amendment_json'=>JSON.generate('version'=>1, 'seed'=>'0'*64))
  U.snapshot([row], joins+[draw])
end

run_entry = lambda do |snapshot, through_directory:|
  row = snapshot.fetch('announcements').first
  change = snapshot.fetch('partner_changes').find { |item| item['kind']=='assigned' }
  names = T::RegistrationProjection.usernames(snapshot.fetch('members'))
  reference = {'author'=>row.fetch('__insertion_user').downcase, 'publication_key'=>row.fetch('publication_key')}
  source = snapshot.merge('publication'=>row, 'usernames'=>names,
    'people'=>(names.keys+[reference.fetch('author')]).uniq)
  scope = {'account'=>reference.fetch('author'), 'account_epoch'=>'entry-test', 'backend_identity'=>'offline-partnership-entry'}
  service = -> { T::TournamentEventNotice.new(kind: 'partnership', source: ->(_reference) { source },
    context: -> { scope }, clock: -> { now }, registry: GameRoomGames::CATALOG) }
  notice = service.call.notices(publication_ref: reference, change_key: change.fetch('key'),
    change_index: change.fetch('index')).first
  scope = scope.merge('account'=>notice.fetch('recipient'))
  proof = service.call.inspect(metadata: notice, sender: row.fetch('__insertion_user'))
  assert_equal('assigned', proof.fetch('change').fetch('kind'), 'The entry must use a valid informational assignment notice')

  calls = []
  args = U.arguments(snapshot, actor: notice.fetch('recipient'), clock: -> { now },
    initial_action: :partner, set_partner: ->(*) { raise 'No partnership mutation was requested' },
    manage_participants: ->(publication) { calls << [:participants, publication.fetch('__id')] })
  driver = PartnershipEntryCallbacks.new
  if through_directory
    T::PublicScreen.new(**args.reject { |key, _| [:snapshot, :publication].include?(key) },
      reference: notice.fetch('publication_ref')).run
  else
    T::PublicPreview.new(**args).wait
  end
  driver.finish
  {calls: calls, views: driver.views}
end

before = run_entry.call(make_snapshot.call(500), through_directory: true)
assert_equal([], before.fetch(:calls), 'Pre-start notice must retain partner selection')
assert(before.fetch(:views).any? { |view| view[:options].any? { |label| label.start_with?('Dissolve partnership with ') } },
  'The control must really open the native partnership editor before start')

started = make_snapshot.call(250)
after = run_entry.call(started, through_directory: true)
puts "Post-start notification entry: #{after.inspect}"
assert_equal([[:participants, 11]], after.fetch(:calls), 'Post-start notification must open participants, not an unusable partnership editor')
assert_equal([], after.fetch(:views), 'Notification entry must not open a partnership editor after start')

ordinary = run_entry.call(started, through_directory: false)
assert_equal([[:participants, 11]], ordinary.fetch(:calls), 'Ordinary preview and notification must use the same post-start destination')
assert(ordinary.fetch(:views).none? { |view| view[:header]=='Team' }, 'Ordinary preview must not expose partner editing after start')
puts 'PASS native informational partnership entry: pre-start editor, post-start participants, same destination for both entry paths'
