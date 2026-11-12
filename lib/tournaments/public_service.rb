# encoding: UTF-8
# frozen_string_literal: true
require_relative 'registration_projection'
require_relative 'tables_gateway'
require_relative 'operation_journal'
require_relative 'schedule_candidate'
require_relative 'fixed_team_schedule_candidate'
require_relative 'server_capacity'
require_relative 'public_invitation_operations'
require_relative 'public_partnership_operations'

module GameRoomTournaments
  # Synchroniczny przypadek użycia: wywołujący uruchamia go poza wątkiem UI.
  # Dwa świeże ograniczone odczyty NIE stanowią transakcji między tabelami.
  # Ograniczenia widoczności, retencji i autentyczności metadanych należą do
  # wybranego providera. Błąd odczytu nigdy nie oznacza pustej listy.
  #
  # Kompozycja dostarcza zaufany gateway tego samego konta i backendu. Opaque
  # backend_identity jest kopiowane bez normalizacji; serwis nie wyprowadza
  # go ze ścieżek i nie wykrywa podmiany providera wewnątrz cudzej bramki.
  # Zmiana backendu wymaga nowej kompozycji i osobnego dziennika, bez migracji.
  # clock zwraca zaufane sekundy Unix UTC (Integer 0..2**63-1); zegar lokalny
  # jest dopuszczalny wyłącznie w jawnym sandboxie. Brak retry, timera i UI.
  # Kompozycja zachowuje byte_limit bramki >= MAX_PAYLOAD_BYTES (65536):
  # publiczne API bramki nie udostępnia mniejszego skonfigurowanego budżetu.
  #
  # list -> głęboko zamrożony Hash RegistrationProjection#to_h, bez filtrowania
  # diagnostyk. publish/join/reconcile -> zamrożony rekord OperationJournal.
  # Niewyjaśniony prepared/attempted zachowuje stan, nie dostaje fikcyjnego
  # statusu ani czasu. confirmed/outside_window nie cofają się do unconfirmed;
  # conflict pozostaje zatrzaśnięty. Konflikt rewizji jest jawnym wyjątkiem.
  # Jeśli istniejący prepared ma inny klucz niż dowiedzione członkostwo tego
  # konta, join zwraca ten prepared bez wysłania i bez fałszywego potwierdzenia.
  # Lista członków nadal pokazuje rzeczywisty zapis innego klienta.
  #
  # Error#code: invalid_backend_identity, backend_changed, invalid_account,
  # account_changed, invalid_tournament_id, unknown_tournament,
  # invalid_operation_id, missing_operation, ambiguous_intent,
  # membership_conflict, invalid_clock, not_open, closed, payload_too_large.
  # Publication::Invalid/Incomplete, OperationJournal::Error/Conflict/Corrupt,
  # StrictJson::IncompatibleRuntime i TablesGateway::Error przechodzą bez
  # udawania pustej listy. Wyjątki programistyczne nie stają się rozłączeniem.
  class PublicService
    include PublicInvitationOperations
    include PublicPartnershipOperations
    Data = Publication::Data

    class Error < StandardError
      attr_reader :code, :details

      def initialize(code, details = {})
        @code = code
        @details = details.freeze
        super(code.to_s)
      end
    end

    def initialize(gateway:, journal:, registry:, user:, backend_identity:, clock:, retention: nil)
      unless Data.text?(backend_identity) && backend_identity.bytesize.between?(1, 4096) &&
          !backend_identity.match?(/[[:cntrl:]\u2028\u2029]/)
        raise Error, :invalid_backend_identity
      end
      @gateway, @journal, @registry = gateway, journal, registry
      @user, @clock = user, clock
      @retention = retention
      @backend_identity = backend_identity.dup.freeze
      guard!
    end

    def list
      snapshot.fetch(:model).to_h
    end

    # One bounded observation for the directory. Result decoration can reuse
    # its raw evidence, but mutations and entry authorization always read afresh.
    def directory_snapshot
      snapshot(progress: true)
    end

    # A scoped, authenticated observation for change notifications. Historical
    # enrollment remains useful for authenticating a withdrawal notification;
    # it never grants permission to enter a match.
    def notification_context(publication_ref:)
      view=publication_snapshot(publication_ref)
      data=view.fetch(:model).to_h
      original=Publication.project(rows:view.fetch(:announcements),registry:@registry,complete:true)['announcements'].first
      raise Publication::Invalid,:missing_publication unless original
      row=data['announcements'].first
      members=data['members'].map{|person|person['account']}
      author=original['__insertion_user'].downcase
      eligible=data['operations'].select{|operation|operation['status']=='confirmed'}.map{|operation|operation['account']}
      row_settings = row && JSON.parse(row['settings_json'])
      pair_game = row && @registry.build(row['game']).team_size(row_settings['game_options'], player_count: row_settings['players_per_match']) == 2
      paired = data.fetch('pairs', []).flat_map { |pair| pair['accounts'] }.sort
      Data.freeze_tree({'publication'=>row,'members'=>data['members'],'pairs'=>data.fetch('pairs',[]),
        'pair_requests'=>data.fetch('pair_requests',[]),'people'=>(members+[author]).uniq,
        'usernames'=>RegistrationProjection.usernames(data['members']).merge(author=>original['__insertion_user']),
        'senders'=>(eligible+[author]).uniq,'invitations'=>data.fetch('invitations',[]),
        'needs_pair_completion'=>!!(pair_game && paired != members.sort),
        'partner_changes'=>data.fetch('partner_changes',[])})
    end

    def publication(publication_ref:)
      model=publication_snapshot(publication_ref).fetch(:model).to_h
      row=model.fetch('announcements').find{|item|item['publication_key']==publication_ref['publication_key'] &&
        item['__insertion_user'].downcase==publication_ref['author'].downcase}
      raise Publication::Invalid,:missing_publication unless row
      row
    end

    def set_partner(tournament_id:, account:, partner:, intent_id:, expected_request_key: nil)
      choose_partnership(tournament_id: tournament_id, account: account, partner: partner,
        intent_id: intent_id, expected_request_key: expected_request_key)
    end

    def edit_tournament(tournament_id:, intent_id:, draft:, rules:, registration_opens_at:, registration_closes_at:, timezone:, expected_generation: nil)
      change_publication(tournament_id: tournament_id, intent_id: intent_id, kind: 'amendment') do |row|
        raise Error, :source_changed if expected_generation && RegistrationProjection.publication_generation(row) != expected_generation
        members = snapshot.fetch(:model).to_h['members'].select { |member| member['tournament_id'] == row['__id'] }
        if members.any? { |member| (registration_opens_at > 0 && member['joined_at'] < registration_opens_at && member['account'] != row['__insertion_user'].downcase) || (registration_closes_at > 0 && member['joined_at'] >= registration_closes_at) }
          raise Error, :registration_members_outside_window
        end
        limit = draft['participant_limit']
        raise Error, :participant_limit_reached if limit && limit < members.size
        Publication.from_draft(draft: draft, registry: @registry, publication_key: row['publication_key'], rules: rules,
          registration_opens_at: registration_opens_at, registration_closes_at: registration_closes_at, timezone: timezone).to_row
      end
    end

    def delete_tournament(tournament_id:, intent_id:, expected_generation: nil)
      change_publication(tournament_id: tournament_id, intent_id: intent_id, kind: 'cancellation') do |row|
        raise Error, :source_changed if expected_generation && RegistrationProjection.publication_generation(row) != expected_generation
        nil
      end
    end

    # Manual controls use the existing authenticated, reconciled amendment
    # journal. They do not fabricate a result or modify an earlier join.
    def change_phase(tournament_id:, action:, intent_id:, expected_generation:)
      raise Error, :invalid_phase_action unless %w[open close start].include?(action)
      change_publication(tournament_id: tournament_id, intent_id: intent_id, kind: 'amendment', starting: action == 'start') do |row|
        raise Error, :source_changed unless RegistrationProjection.publication_generation(row) == expected_generation
        # Resolve a repeated Start intent before preparing any new pairs or
        # rejecting the already-started publication in the shared write path.
        complete_partnerships(tournament_id: tournament_id, starting: true) if action == 'start'
        now=boundary{@clock.call}
        revised=Data.copy(row.slice(*Publication::COLUMNS))
        timing=TournamentTiming.schedule(row)
        unless TournamentTiming.optional?(row)
          timing.merge!('starts_at'=>TournamentTiming.starts_at(row),'deadline_at'=>TournamentTiming.deadline_at(row))
          revised['schema_version']=2
        end
        case action
        when 'open'
          raise Error,:already_open if TournamentTiming.registration_open?(row,now)
          revised['registration_opens_at']=now
          revised['registration_closes_at']=0
        when 'close'
          raise Error,:not_open unless TournamentTiming.registration_open?(row,now)
          revised['registration_closes_at']=now
        when 'start'
          timing['starts_at']=now
          revised['registration_opens_at']=[revised['registration_opens_at'],now].min
          revised['registration_closes_at']=now
        end
        revised['schedule_json']=JSON.generate(timing)
        checked=Publication.project(rows:[revised.merge(row.slice('__id','__insertion_user','__insertion_time'))],registry:@registry,complete:true)
        raise Error,:invalid_phase_action unless checked['diagnostics'].empty?
        if action=='start'
          # Validate the complete roster and pairs before freezing it. This is
          # not a server transaction; the final source is checked again at entry.
          view=snapshot
          settings=JSON.parse(row['settings_json'])
          members=view[:model].to_h['members'].select{|person|person['tournament_id']==row['__id']}
          raise Error,:too_few_players if members.size<settings['players_per_match']
          if @registry.build(row['game']).team_size(settings['game_options'],player_count:settings['players_per_match'])==2
            pairs=(view[:model].to_h['pairs'] || []).select{|pair|pair['tournament_id']==row['__id']}.flat_map{|pair|pair['accounts']}.sort
            raise Error,:incomplete_pairs unless pairs==members.map{|person|person['account']}.sort
          end
          # Reuse publication's real planner limits for the CURRENT roster.
          # Never manufacture a closed projection: same-second joins retain
          # their authenticated chronology, and invalid Start remains unsent.
          ServerCapacity.validate!(registry: @registry, game_id: row['game'],
            settings: settings.merge('participant_limit' => members.size))
        end
        revised
      end
    end

    def withdraw(tournament_id:)
      raise Error, :invalid_tournament_id unless Data.integer?(tournament_id, 1)
      view = snapshot
      row = view.fetch(:model).to_h['announcements'].find { |item| item['alias_ids'].include?(tournament_id) }
      raise Error, :unknown_tournament unless row
      epoch = registration_epoch(row, view)
      intent = "withdrawal:#{row['__id']}" + (epoch.zero? ? '' : ":after:#{epoch}")
      existing = boundary { @journal.find(kind: 'withdrawal', intent_id: intent) }
      member = view.fetch(:model).to_h['members'].find { |person| person['tournament_id'] == row['__id'] && person['account'] == @journal.owner }
      existing ||= departure_record('withdrawal', row, epoch, view) unless member
      return reconcile_record(existing, view) if existing && existing['status'] != 'prepared'
      now = boundary { @clock.call }
      raise Error, :invalid_clock unless Data.integer?(now)
      raise Error, :tournament_started if TournamentTiming.started?(row,now)
      unless view.fetch(:model).to_h['members'].any? { |person| person['tournament_id'] == row['__id'] && person['account'] == @journal.owner }
        raise Error, :not_registered
      end
      values = RegistrationProjection.withdrawal_values(tournament_id: row['__id'], operation_key: SecureRandom.uuid)
      record = existing || boundary { @journal.prepare(kind: 'withdrawal', intent_id: intent, values: values) }
      # A fresh clock check precedes the sole durable claim; readback resolves uncertainty.
      before_tournament_start!(row)
      attempt(record)
    end

    def remove_participant(tournament_id:, account:)
      raise Error, :invalid_tournament_id unless Data.integer?(tournament_id, 1)
      account = Data.account(account).downcase
      view = snapshot
      row = view.fetch(:model).to_h['announcements'].find { |item| item['alias_ids'].include?(tournament_id) }
      raise Error, :unknown_tournament unless row
      raise Error, :not_organizer unless row['__insertion_user'].downcase == @journal.owner
      epoch = registration_epoch(row, view, account: account)
      intent = "removal:#{row['__id']}:#{account}" + (epoch.zero? ? '' : ":after:#{epoch}")
      existing = boundary { @journal.find(kind: 'removal', intent_id: intent) }
      member = view.fetch(:model).to_h['members'].find { |person| person['tournament_id'] == row['__id'] && person['account'] == account }
      existing ||= departure_record('removal', row, epoch, view) unless member
      return reconcile_record(existing, view) if existing && existing['status'] != 'prepared'
      now = boundary { @clock.call }
      raise Error, :invalid_clock unless Data.integer?(now)
      raise Error, :tournament_started if TournamentTiming.started?(row,now)
      unless view.fetch(:model).to_h['members'].any? { |person| person['tournament_id'] == row['__id'] && person['account'] == account }
        raise Error, :not_registered
      end
      values = RegistrationProjection.join_values(tournament_id: row['__id'], operation_key: SecureRandom.uuid).merge('kind' => 'removal', 'account' => account)
      record = existing || boundary { @journal.prepare(kind: 'removal', intent_id: intent, values: values) }
      before_tournament_start!(row)
      attempt(record)
    end

    # Oryginalna projekcja zachowuje diagnostyki i dowody; members nie jest jej zamiennikiem.
    def schedule_candidate(publication_ref:, scoped: false)
      boundary do
        view = scoped ? publication_snapshot(publication_ref) : snapshot
        observed_at = boundary { @clock.call }
        raise Error, :invalid_clock unless Data.integer?(observed_at)
        ScheduleCandidate.build(projection: view.fetch(:model), publication_ref: publication_ref,
          backend_identity: @backend_identity, observed_at: observed_at)
      end
    end

    def start_notice_source(publication_ref:)
      boundary do
        view=publication_snapshot(publication_ref)
        observed=ScheduleSource.build(projection:view.fetch(:model),publication_ref:publication_ref,
          backend_identity:@backend_identity,observed_at:@clock.call)
        Data.freeze_tree({'complete'=>true,'publication'=>observed.fetch(:row),
          'usernames'=>RegistrationProjection.usernames(observed.fetch(:members)),
          'participants'=>observed.fetch(:members).map{|member|member.fetch('account')}})
      end
    end

    def server_schedule_source(publication_ref:, directory: nil, evidence_only: false)
      boundary do
        view = directory ? scoped_snapshot(publication_ref, directory.fetch(:announcements), directory.fetch(:registrations)) :
          publication_snapshot(publication_ref, apply_retention: !evidence_only)
        observed_at = boundary { @clock.call }
        raise Error, :invalid_clock unless Data.integer?(observed_at)
        observed = ScheduleSource.build(projection: view.fetch(:model), publication_ref: publication_ref,
          backend_identity: @backend_identity, observed_at: observed_at)
        settings = observed.fetch(:settings)
        row = observed.fetch(:row)
        game = @registry.build(row['game'])
        if game.team_size(settings['game_options'], player_count: settings['players_per_match']) == 2
          pairs = (view.fetch(:model).to_h['pairs'] || []).select { |pair| pair['tournament_id'] == row['__id'] }.map { |pair| pair['accounts'].sort }.sort
          accounts = observed.fetch(:members).map { |member| member['account'] }.sort
          raise Publication::Invalid.new(:too_few_players, count: accounts.length, minimum: settings['players_per_match']) if accounts.length<settings['players_per_match']
          unless pairs.size >= 2 && pairs.flatten.sort == accounts
            raise Publication::Invalid.new(:incomplete_pairs, count: (accounts-pairs.flatten).length)
          end
          membership = {'version' => 1, 'kind' => 'fixed-teams', 'units' => pairs.each_with_index.map { |pair, index| {'unit_id' => format('team-%03d', index + 1), 'accounts' => pair} }}
          candidate = FixedTeamScheduleCandidate.build(projection: view.fetch(:model), publication_ref: publication_ref,
            backend_identity: @backend_identity, observed_at: observed_at, membership: membership,
            team_template: settings['game_options']['team_seats'] || [0, 1, 0, 1]).to_h
        else
          candidate = ScheduleCandidate.build(projection: view.fetch(:model), publication_ref: publication_ref,
            backend_identity: @backend_identity, observed_at: observed_at).to_h
        end
        row = view.fetch(:model).to_h.fetch('announcements').find do |item|
          item['publication_key'] == candidate['publication_ref']['publication_key'] &&
            item['__insertion_user'].downcase == candidate['publication_ref']['author']
        end
        Data.freeze_tree({'tournament_id' => row.fetch('__id'), 'candidate' => candidate,
          'usernames'=>RegistrationProjection.usernames(observed.fetch(:members)),
          'deadline_at'=>TournamentTiming.deadline_at(row)})
      end
    end

    # Pełny odczyt wykonawczy: kandydat i surowe dowody z tej samej projekcji.
    # Nadal dwa odczyty tabel, nie transakcja serwerowa.
    def execution_source(publication_ref:)
      reference = Data.freeze_tree(Data.copy(publication_ref))
      boundary do
        view = snapshot
        observed_at = boundary { @clock.call }
        raise Error, :invalid_clock unless Data.integer?(observed_at)
        candidate = ScheduleCandidate.build(projection: view.fetch(:model), publication_ref: reference,
          backend_identity: @backend_identity, observed_at: observed_at)
        Data.freeze_tree(Data.copy({'candidate' => candidate.to_h, 'projection' => view.fetch(:model).to_h,
          'announcements' => view.fetch(:announcements), 'registrations' => view.fetch(:registrations)},
          max_bytes: 33_554_432, max_nodes: 524_288, max_depth: 12))
      end
    end

    # Jawne ekipy korzystają z tej samej obserwacji, lecz nie z planera osób.
    def fixed_team_execution_source(publication_ref:, membership:, team_template:)
      input = Data.freeze_tree(Data.copy({'publication_ref' => publication_ref,
        'membership' => membership, 'team_template' => team_template}))
      boundary do
        view = snapshot
        observed_at = boundary { @clock.call }
        raise Error, :invalid_clock unless Data.integer?(observed_at)
        candidate = FixedTeamScheduleCandidate.build(projection: view.fetch(:model),
          publication_ref: input['publication_ref'], membership: input['membership'],
          team_template: input['team_template'], backend_identity: @backend_identity, observed_at: observed_at)
        Data.freeze_tree(Data.copy({'candidate' => candidate.to_h, 'projection' => view.fetch(:model).to_h,
          'announcements' => view.fetch(:announcements), 'registrations' => view.fetch(:registrations)},
          max_bytes: 33_554_432, max_nodes: 524_288, max_depth: 12))
      end
    end

    def publish(draft:, intent_id:, rules:, registration_opens_at:, registration_closes_at:, timezone:)
      previous = boundary { @journal.find(kind: 'publication', intent_id: intent_id) }
      key = previous ? previous['values']['publication_key'] : SecureRandom.uuid
      values = Publication.from_draft(draft: draft, registry: @registry, publication_key: key,
        rules: rules, registration_opens_at: registration_opens_at,
        registration_closes_at: registration_closes_at, timezone: timezone).to_row
      record = boundary { @journal.prepare(kind: 'publication', intent_id: intent_id, values: values) }
      record = resolve_publication(record, snapshot)
      return record unless record['status'] == 'prepared'

      attempt(record)
    end

    def join(tournament_id:)
      raise Error, :invalid_tournament_id unless Data.integer?(tournament_id, 1)

      view = snapshot
      row = view.fetch(:model).to_h['announcements'].find { |item| item['alias_ids'].include?(tournament_id) }
      if !row && view[:evidence_model] && view[:evidence_model].to_h['announcements'].any? { |item| item['alias_ids'].include?(tournament_id) }
        raise Error, :unknown_tournament
      end
      aliases = row ? row['alias_ids'] : [tournament_id]
      epoch = row ? registration_epoch(row, view) : 0
      intent = "join:#{row ? row['__id'] : tournament_id}" + (epoch.zero? ? '' : ":after:#{epoch}")
      matches = boundary { @journal.list }.select do |record|
        record['kind'] == 'join' && aliases.include?(record['values']['tournament_id']) && (epoch.zero? || record['intent_id'] == intent)
      end
      raise Error, :ambiguous_intent if matches.length > 1

      existing = matches.first
      if existing
        existing = resolve_join(existing, view)
        if row && existing['status'] == 'confirmed' && !view.fetch(:model).to_h['members'].any? { |person| person['tournament_id'] == row['__id'] && person['account'] == @journal.owner }
          raise Error, :registration_withdrawn
        end
        return existing unless row && existing['status'] == 'prepared'
      end
      raise Error, :unknown_tournament unless row

      registration_problem!(row, view)
      return existing if existing && !remote_operations(row, view).empty?

      unless existing
        adopted = adopt_join(row, view)
        return adopted if adopted
      end
      preflight(row)
      record = existing || boundary do
        values = RegistrationProjection.join_values(tournament_id: row['__id'], operation_key: SecureRandom.uuid)
        @journal.prepare(kind: 'join', intent_id: intent, values: values)
      end
      finish_join(record)
    end

    # A replayed publication must not undo a later organizer withdrawal.
    def register_creator(publication_record:)
      return nil unless publication_record['status'] == 'confirmed'
      view = snapshot
      row = view.fetch(:model).to_h['announcements'].find do |item|
        item['publication_key'] == publication_record['values']['publication_key'] && item['__insertion_user'].downcase == @journal.owner
      end
      return nil unless row
      return {'status' => 'withdrawn'}.freeze unless registration_epoch(row, view).zero?
      join(tournament_id: row['__id'])
    rescue TablesGateway::UnconfirmedWrite
      guard!
      {'status' => 'attempted'}.freeze
    rescue Error => error
      {'status' => 'blocked', 'reason' => error.code.to_s}.freeze
    end

    # Wyłącznie odczyt i resolve; nigdy claim ani append. Błędy bramki (także
    # UnconfirmedWrite) oraz dziennika są propagowane. Po próbie zapisu UI ma
    # pokazać niepewność i oferować reconcile, NIE ponowną wysyłkę.
    def reconcile(operation_id:)
      unless Data.text?(operation_id) && operation_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
        raise Error, :invalid_operation_id
      end
      record = boundary { @journal.fetch(operation_id) }
      raise Error, :missing_operation unless record

      reconcile_record(record, snapshot)
    end

    private

    def registration_epoch(row, view, account: @journal.owner)
      operations = view.fetch(:model).to_h['operations']
      eligible = operations.select { |op| op['tournament_id'] == row['__id'] && op['status'] == 'confirmed' }.flat_map { |op| op['eligible_ids'] }
      events = view.fetch(:registrations).select do |event|
        eligible.include?(event['__id']) && row['alias_ids'].include?(event['tournament_id']) &&
          ((event['kind'] == 'withdrawal' && event['__insertion_user'].downcase == account) ||
           (event['kind'] == 'removal' && event['account'] == account))
      end
      events.max_by { |event| [event['__insertion_time'], event['__id']] }&.fetch('__id') || 0
    end

    def departure_record(kind, row, epoch, view)
      event = view.fetch(:registrations).find { |item| item['__id'] == epoch }
      return nil unless event && event['__insertion_user'].downcase == @journal.owner
      boundary { @journal.list }.find do |record|
        record['kind'] == kind && row['alias_ids'].include?(record['values']['tournament_id']) &&
          record['values']['operation_key'] == event['operation_key']
      end
    end

    def change_publication(tournament_id:, intent_id:, kind:, starting: false)
      raise Error, :invalid_tournament_id unless Data.integer?(tournament_id, 1)
      previous = boundary { @journal.find(kind: kind, intent_id: intent_id) }
      return reconcile_record(previous, snapshot) if previous && previous['status'] != 'prepared'
      view = snapshot
      row = view.fetch(:model).to_h['announcements'].find { |item| item['alias_ids'].include?(tournament_id) }
      raise Error, :unknown_tournament unless row
      unresolved_mutation!(row, view, %w[amendment cancellation], intent_id)
      raise Error, :not_organizer unless row['__insertion_user'].downcase == @journal.owner
      before_tournament_start!(row) unless kind=='cancellation'
      revised = yield row
      before_tournament_start!(revised) if revised && !starting
      generation = RegistrationProjection.publication_generation(row)
      values = RegistrationProjection.join_values(tournament_id: row['__id'], operation_key: SecureRandom.uuid).merge('kind' => kind, 'publication_generation' => generation)
      values['amendment_json'] = JSON.generate(revised) if revised
      record = previous || boundary { @journal.prepare(kind: kind, intent_id: intent_id, values: values) }
      fresh = snapshot.fetch(:model).to_h['announcements'].find { |item| item['__id'] == row['__id'] }
      raise Error, :source_changed unless fresh && RegistrationProjection.publication_generation(fresh) == record['values']['publication_generation']
      before_tournament_start!(fresh) unless kind=='cancellation'
      attempt(record)
    end

    def unresolved_mutation!(row, view, kinds, intent_id)
      records = boundary { @journal.list }.select do |record|
        kinds.include?(record['kind']) && record['intent_id'] != intent_id && row['alias_ids'].include?(record['values']['tournament_id']) && %w[prepared attempted].include?(record['status'])
      end
      records.each do |record|
        resolved = reconcile_record(record, view)
        raise Error, :pending_operation if %w[prepared attempted].include?(resolved['status'])
      end
    end

    def before_tournament_start!(row)
      now = boundary { @clock.call }
      raise Error, :invalid_clock unless Data.integer?(now)
      raise Error, :tournament_started if TournamentTiming.started?(row,now)
    end

    def finish_join(record)
      view = snapshot
      record = resolve_join(record, view)
      return record unless record['status'] == 'prepared'

      row = view.fetch(:model).to_h['announcements'].find do |item|
        item['alias_ids'].include?(record['values']['tournament_id'])
      end
      raise Error, :unknown_tournament unless row

      registration_problem!(row, view)
      return record unless remote_operations(row, view).empty?

      preflight(row)
      attempt(record)
    end

    def remote_operations(row, view)
      epoch = registration_epoch(row, view)
      departure = view.fetch(:registrations).find { |item| item['__id'] == epoch }
      join_ids = view.fetch(:registrations).select do |item|
        item['kind'] == 'join' && (!departure || ([item['__insertion_time'], item['__id']] <=> [departure['__insertion_time'], departure['__id']]) == 1)
      end.map { |item| item['__id'] }
      view.fetch(:model).to_h['operations'].select do |item|
        item['tournament_id'] == row['__id'] && item['account'] == @journal.owner && !(item['record_ids'] & join_ids).empty?
      end
    end

    def registration_problem!(row, view)
      ids = view.fetch(:registrations).filter_map do |raw|
        begin
          raw['__id'] if row['alias_ids'].include?(raw['tournament_id']) &&
            Data.account(raw['__insertion_user']).downcase == @journal.owner
        rescue Publication::Invalid
          nil
        end
      end
      problem = view.fetch(:model).to_h['diagnostics']['registrations'].any? do |item|
        item['code'] != 'outside_window' && !(item['ids'] & ids).empty?
      end
      raise Error, :membership_conflict if problem
    end

    # Przejmujemy faktyczny klucz i pierwotny alias zwalidowanej operacji,
    # nigdy nie potwierdzamy nowego losowego klucza dowodem innego klienta.
    def adopt_join(row, view)
      data = view.fetch(:model).to_h
      operations = remote_operations(row, view)
      return nil if operations.empty?

      member = data['members'].find { |item| item['tournament_id'] == row['__id'] && item['account'] == @journal.owner }
      id = member ? member['registration_id'] : operations.flat_map { |item| item['record_ids'] }.min
      source = view.fetch(:registrations).find { |item| item['__id'] == id }
      values = RegistrationProjection.join_values(tournament_id: source['tournament_id'], operation_key: source['operation_key'])
      epoch = registration_epoch(row, view)
      intent = "join:#{row['__id']}" + (epoch.zero? ? '' : ":after:#{epoch}")
      record = boundary { @journal.prepare(kind: 'join', intent_id: intent, values: values) }
      resolve_join(record, view)
    end

    # To tylko lokalna odmowa próby; o członkostwie decyduje metadana insertu.
    def preflight(row)
      now = boundary { @clock.call }
      raise Error, :invalid_clock unless Data.integer?(now)
      creator = row['__insertion_user'].downcase == @journal.owner && now >= row['__insertion_time']
      raise Error, :closed if TournamentTiming.registration_closed?(row,now)
      raise Error, :not_open unless creator || TournamentTiming.registration_open?(row,now)
      limit = JSON.parse(row['settings_json'])['participant_limit']
      if limit
        members = snapshot.fetch(:model).to_h.fetch('members').select { |member| member['tournament_id'] == row['__id'] }
        raise Error, :participant_limit_reached if members.size >= limit && members.none? { |member| member['account'] == @journal.owner }
      end
    end

    def attempt(record)
      return record unless record['status'] == 'prepared'

      validate_payload(record['values'])
      claimed = boundary { @journal.claim(record['id']) }
      return reconcile(operation_id: record['id']) unless claimed

      boundary { @gateway.append(claimed['table_name'], claimed['values']) }
      reconcile_record(claimed, snapshot)
    end

    def reconcile_record(record, view)
      record['kind'] == 'publication' ? resolve_publication(record, view) : resolve_join(record, view)
    end

    def resolve_join(record, view)
      values = record['values']
      # Expiry hides the tournament, not evidence of an earlier confirmed write.
      model = view.fetch(:evidence_model, view.fetch(:model))
      status = model.operation_status(tournament_id: values['tournament_id'], account: @journal.owner,
        operation_key: values['operation_key'])
      operation = model.to_h['operations'].find do |item|
        item['account'] == @journal.owner && item['operation_key'] == values['operation_key']
      end
      target = model.to_h['announcements'].find { |row| row['alias_ids'].include?(values['tournament_id']) }
      if !target && record['kind'] == 'cancellation'
        target = Publication.project(rows: view.fetch(:announcements), registry: @registry, complete: true)['announcements'].find { |row| row['alias_ids'].include?(values['tournament_id']) }
      end
      status = 'conflict' if operation && (!target || operation['tournament_id'] != target['__id'])
      return record if status == 'unconfirmed'

      ids = operation ? operation['record_ids'] : validated_join_ids(view, values['operation_key'])
      pairing_applied = if (['pairing'] + Partnerships::KINDS).include?(record['kind']) && status == 'confirmed'
        model.pairing_applied?(account: @journal.owner, operation_key: values['operation_key'])
      end
      resolve(record, status, key: values['operation_key'], ids: ids,
        canonical_id: target && target['__id'], pairing_applied: pairing_applied)
    end

    def validated_join_ids(view, key)
      view.fetch(:registrations).flat_map do |raw|
        next [] unless Data.group_hint(raw, 'operation_key') == [@journal.owner, key]

        model = RegistrationProjection.build(announcements: view.fetch(:announcements),
          registrations: [raw], registry: @registry, complete: true)
        model.to_h['operations'].flat_map { |operation| operation['record_ids'] }
      end.uniq.sort
    end

    def validate_payload(values)
      raise Error, :payload_too_large if JSON.generate(values).bytesize > TablesGateway::MAX_PAYLOAD_BYTES
    end

    def resolve_publication(record, view)
      key = record['values']['publication_key']
      data = {'announcements' => Publication.project(rows: view.fetch(:announcements), registry: @registry, complete: true)['announcements'], 'diagnostics' => view.fetch(:model).to_h['diagnostics']}
      row = data['announcements'].find do |item|
        item['publication_key'] == key && item['__insertion_user'].downcase == @journal.owner
      end
      conflict = data['diagnostics']['announcements'].any? do |item|
        item['code'] == 'key_conflict' && item['account'] == @journal.owner && item['key'] == key
      end
      return record unless row || conflict

      matches = row && publication_content(row).eql?(publication_content(record['values']))
      status = conflict || !matches ? 'conflict' : 'confirmed'
      ids = row ? row['alias_ids'] : validated_publication_ids(view, key)
      resolve(record, status, key: key, ids: ids, canonical_id: row && row['__id'])
    end

    def publication_content(values)
      Publication::COLUMNS.to_h do |column|
        value = values[column]
        if %w[settings_json schedule_json].include?(column)
          value = StrictJson.parse(value, max_nesting: 8)
        end
        [column, value]
      end
    end

    def validated_publication_ids(view, key)
      view.fetch(:announcements).flat_map do |raw|
        next [] unless Data.group_hint(raw, 'publication_key') == [@journal.owner, key]

        Publication.project(rows: [raw], registry: @registry, complete: true)['announcements'].map { |row| row['__id'] }
      end.uniq.sort
    end

    def resolve(record, status, key:, ids:, canonical_id:, pairing_applied: nil)
      # Dowód ograniczony niezależnie od rozmiaru aliasów. Licznik jawnie
      # informuje o skróceniu listy ID; decyzja korzysta z całej projekcji.
      return record if record['status'] == 'conflict'

      evidence = {'status' => status, 'record_ids' => ids.first(64), 'record_count' => ids.length,
        'canonical_id' => canonical_id, 'author' => @journal.owner, 'key' => key}
      evidence['pairing_applied'] = pairing_applied unless pairing_applied.nil?
      boundary { @journal.resolve(record['id'], status: status, evidence: evidence, expected_revision: record['revision']) }
    end

    def guard!
      account = Data.account(@user.call).downcase
      raise Error, :account_changed unless account == @journal.owner
      raise Error, :backend_changed unless @backend_identity == @journal.backend_identity
    rescue Publication::Invalid
      raise Error, :invalid_account
    end

    def boundary
      guard!
      completed = false
      begin
        result = yield
        completed = true
        result
      ensure
        guard_after(completed ? nil : $!)
      end
    end

    def guard_after(failure)
      guard!
    rescue Error
      # Kontrola nadal następuje, ale nie zasłania pierwotnego wyjątku,
      # zwłaszcza błędu programu lub UnconfirmedWrite z danymi uzgodnienia.
      raise unless failure
    end

    def snapshot(progress: false)
      announcements = boundary { @gateway.read_rows('tournament_announcements') }
      registrations = boundary { @gateway.read_rows('tournament_registrations') }
      model = RegistrationProjection.build(announcements: announcements, registrations: registrations,
        registry: @registry, complete: true)
      retain({model: model, announcements: announcements, registrations: registrations}, progress: progress)
    end

    # Complete evidence for one selected publication, including every alias and
    # its registration diagnostics. Unrelated broken announcements do not belong
    # to this query scope. No diagnostics of the selected tournament are removed.
    def publication_snapshot(reference, apply_retention: true)
      key = ScheduleSource.reference(reference).fetch('publication_key')
      author = Data.account(reference.fetch('author'))
      announcements = boundary { @gateway.read_rows('tournament_announcements',
        where: {'publication_key' => key}) }
      # References normalize names, while SDK metadata retains spelling. Do
      # not rely on a case-insensitive equality operator the SDK does not offer.
      announcements=announcements.select{|row|row['__insertion_user'].to_s.downcase==author.downcase}
      ids = announcements.map { |row| row.fetch('__id') }
      registrations = ids.empty? ? [] : boundary { @gateway.read_rows('tournament_registrations',
        where: {'tournament_id' => {'in' => ids}}) }
      model = RegistrationProjection.build(announcements: announcements, registrations: registrations,
        registry: @registry, complete: true)
      view={model: model, announcements: announcements, registrations: registrations}
      apply_retention ? retain(view) : view
    end

    def scoped_snapshot(reference, announcements, registrations)
      key = ScheduleSource.reference(reference).fetch('publication_key')
      author = Data.account(reference.fetch('author')).downcase
      announcements = announcements.select { |row| row['publication_key'] == key && row['__insertion_user'].to_s.downcase == author }
      ids = announcements.map { |row| row.fetch('__id') }
      registrations = registrations.select { |row| ids.include?(row['tournament_id']) }
      model = RegistrationProjection.build(announcements: announcements, registrations: registrations,
        registry: @registry, complete: true)
      {model: model, announcements: announcements, registrations: registrations}
    end

    def retain(view, progress: false)
      @retention ? boundary { @retention.call(view, progress: progress) } : view
    end
  end
end
