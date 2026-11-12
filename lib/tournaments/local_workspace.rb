# encoding: UTF-8
# frozen_string_literal: true
require 'digest'
require_relative 'local_test_tables'
require_relative 'public_service'
require_relative 'local_readiness_connection'
require_relative 'local_fixed_team_connection'
require_relative 'local_individual_connection'
require_relative '../game_room_localization'
require_relative '../game_content'

module GameRoomTournaments
  # Jawny sandbox, bez serwera i importu szkiców/rosteru. user określa wyłącznie
  # izolację plików rzeczywistego konta. actor jest oddzielnie wybraną osobą
  # TESTOWĄ; zmiana aktora wymaga nowej instancji, nie przepięcia dziennika.
  # local_test:system jest opaque metadaną lokalnej strefy komputera, NIE IANA.
  class LocalWorkspace
    using GameRoomLocalization::Translations
    Data = Publication::Data
    TIMEZONE = 'local_test:system'.freeze
    OPERATION_ERRORS = [Publication::Invalid, PublicService::Error, TablesGateway::Error,
      LocalTestTables::Error, OperationJournal::Error, StrictJson::IncompatibleRuntime,
      IOError, SystemCallError].freeze
    attr_reader :actor, :last_error, :readiness_session, :registry

    def initialize(program:, registry:, user:, actor:, alert:, clock: -> { Time.now.to_i }, readiness_session: nil)
      @readiness_session = readiness_session
      @actor = Data.account(actor).freeze
      @owner = Data.account(user.call).downcase.freeze
      @program, @registry, @user, @alert, @clock = program, registry, user, alert, clock
    end

    def mode_label
      GameRoomContent.utf8(_("Local test — this computer only"))
    end

    def timezone
      TIMEZONE
    end

    def load
      access(_("Loading local test tournaments")) { @service.list }
    end

    def entry_load(context:, lease:)
      access(_("Loading local test tournaments"), entry_guard: -> { context.current?(lease) }) { @service.list }
    end

    def schedule_candidate(publication_ref:, context: nil, lease: nil)
      guard = context && -> { context.current?(lease) }
      access(_("Reading a local test schedule candidate"), input: publication_ref, entry_guard: guard) do |reference|
        begin
          @service.schedule_candidate(publication_ref: reference)
        rescue Publication::Invalid => error
          raise unless [:registration_open, :no_players, :too_few_players, :too_many_players,
            :plan_too_large, :unsupported_format, :invalid_group_configuration, :unresolved_source_diagnostics, :missing_publication].include?(error.code)
          {reason: error.code}.freeze
        end
      end
    end

    # Odczyt deskryptora nie inicjuje magazynu ani nie udostępnia providera.
    def entry_descriptor
      Data.freeze_tree(Data.copy({'owner' => @owner, 'actor' => @actor,
        'backend_identity' => @provider&.backend_identity}))
    end

    def publish(draft:, intent_id:, rules:, registration_opens_at:, registration_closes_at:, timezone:)
      input = {'draft' => draft, 'intent_id' => intent_id, 'rules' => rules,
        'registration_opens_at' => registration_opens_at,
        'registration_closes_at' => registration_closes_at, 'timezone' => timezone}
      access(_("Publishing a local test tournament"), input: input, writing: true) do |copy|
        raise Publication::Invalid, :local_timezone unless [TIMEZONE, 'UTC'].include?(copy['timezone'])
        record = @service.publish(**copy.transform_keys(&:to_sym))
        enrollment = @service.register_creator(publication_record: record)
        record.merge('organizer_registration' => enrollment).freeze
      end
    end

    def join(tournament_id)
      access(_("Joining a local test tournament"), writing: true) { @service.join(tournament_id: tournament_id) }
    end

    def withdraw(tournament_id)
      access(_("Leaving a local test tournament"), input: tournament_id, writing: true) { |id| @service.withdraw(tournament_id: id) }
    end

    def set_partner(tournament_id, account, partner, intent_id)
      access(_("Saving tournament pair"), input: [tournament_id, account, partner, intent_id], writing: true) do |values|
        @service.set_partner(tournament_id: values[0], account: values[1], partner: values[2], intent_id: values[3])
      end
    end
    def partnership_action(id, action, partner, request_key, intent)
      access(_("Saving tournament pair"), input: [id, action, partner, request_key, intent], writing: true) do |values|
        @service.partnership_action(tournament_id: values[0], action: values[1], partner: values[2],
          request_key: values[3], intent_id: values[4])
      end
    end

    def edit_tournament(tournament_id:, intent_id:, **attributes)
      access(_("Editing tournament"), input: attributes.transform_keys(&:to_s), writing: true) do |copy|
        @service.edit_tournament(tournament_id: tournament_id, intent_id: intent_id, **copy.transform_keys(&:to_sym))
      end
    end

    def delete_tournament(id, intent, generation = nil)
      access(_("Deleting tournament"), input: [id, intent, generation], writing: true) { |copy| @service.delete_tournament(tournament_id: copy[0], intent_id: copy[1], expected_generation: copy[2]) }
    end

    def remove_participant(tournament_id, account)
      access(_("Removing a local test participant"), input: [tournament_id, account], writing: true) { |values| @service.remove_participant(tournament_id: values[0], account: values[1]) }
    end

    def operations
      access(_("Loading local test operations")) { @journal.list }
    end

    def reconcile(operation_id)
      access(_("Checking a local test operation"), input: operation_id) do |id|
        record = @service.reconcile(operation_id: id)
        if record['kind'] == 'publication'
          record = record.merge('organizer_registration' => @service.register_creator(publication_record: record)).freeze
        end
        record
      end
    end

    # Wyłącznie worker Work/Tasks.start; ta droga nie używa Tasks.run ani UI.
    def readiness_connection(context:, lease:)
      raise ReadinessContract::Blocked, :context_unavailable unless @readiness_session
      connection = nil
      primary = nil
      adopted = false
      begin
        boundary do
          compose
          raise ReadinessContract::Blocked, :context_changed unless context.current?(lease)
          directory = File.join(@root, 'tournament-readiness-k03-' + Digest::SHA256.hexdigest(@owner))
          connection = LocalReadinessConnection.new(directory: File.join(directory, 'backend'),
            journal_directory: File.join(directory, 'journals'), actor: @actor,
            clock: -> { boundary { @clock.call } },
            source: ->(reference) { boundary { @service.schedule_candidate(publication_ref: reference) } },
            session: @readiness_session, program: @program, owner_reader: @user, entry: context, lease: lease)
        end
        adopted = true
        connection
      rescue Exception => error
        primary = error
        raise error, cause: error.cause
      ensure
        begin
          connection&.close(primary: primary) unless adopted
        ensure
          raise primary, cause: primary.cause if primary
        end
      end
    end

    # Jedna fabryka ścieżki również dla przyszłego producenta akceptacji FT1.
    # Wywoływana w workerze; brak skanowania katalogów albo importu fixture.
    def fixed_team_plan_directory
      boundary do
        compose
        File.join(@root, 'tournament-local-test-' + Digest::SHA256.hexdigest(@owner), 'plans').freeze
      end
    end

    def fixed_team_connection(context:, lease:, session:)
      execution_connection(connection_class: LocalFixedTeamConnection, context: context, lease: lease, session: session)
    end

    def individual_connection(context:, lease:, session:)
      execution_connection(connection_class: LocalIndividualConnection, context: context, lease: lease, session: session)
    end

    def execution_connection(connection_class:, context:, lease:, session:)
      connection = nil
      adopted = false
      primary = nil
      begin
        directory = fixed_team_plan_directory
        raise ReadinessContract::Blocked, :context_changed unless context.current?(lease)
        connection = connection_class.new(directory: directory, tables: @provider, journal: @journal,
          actor: @actor, registry: @registry, clock: -> { boundary { @clock.call } },
          session: session, program: @program, owner_reader: @user, entry: context, lease: lease)
        raise ReadinessContract::Blocked, :context_changed unless context.current?(lease)
        adopted = true
        connection
      rescue Exception => error
        primary = error
        raise error, cause: error.cause
      ensure
        begin
          connection&.close(primary: primary) unless adopted
        ensure
          raise primary, cause: primary.cause if primary
        end
      end
    end

    def fixed_team_plan(action:, input:, context:, lease:, session:)
      plan_operation(connection_method: :fixed_team_connection, label: _("Fixed-team plan"), action: action, input: input, context: context, lease: lease, session: session)
    end

    def individual_plan(action:, input:, context:, lease:, session:)
      plan_operation(connection_method: :individual_connection, label: _("Individual plan"), action: action, input: input, context: context, lease: lease, session: session)
    end

    def tournament_overview(publication_ref:, context:, lease:, session:)
      guard = -> { context.current?(lease) }
      access(_("Loading local test tournaments"), input: publication_ref, entry_guard: guard) do |reference|
        connection = nil
        begin
          snapshot = @service.list
          publication = snapshot['announcements'].find { |row| row['__insertion_user'].downcase == reference['author'].downcase && row['publication_key'] == reference['publication_key'] }
          starts = publication && RegistrationProjection.local_start(publication)
          if publication && !starts
            raise Publication::Invalid, TournamentTiming.registration_closed?(publication, @clock.call) ? :tournament_not_started : :registration_open
          end
          settings = publication && JSON.parse(publication['settings_json'])
          team_game = publication && @registry.build(publication['game']).team_size(settings['game_options'], player_count: settings['players_per_match']) == 2
          if team_game
            raise Publication::Invalid, :registration_open if @clock.call < publication['registration_closes_at']
            pairs = (snapshot['pairs'] || []).select { |row| row['tournament_id'] == publication['__id'] }.map { |row| row['accounts'] }.sort
            roster = snapshot['members'].select { |row| row['tournament_id'] == publication['__id'] }.map { |row| row['account'] }.sort
            raise Publication::Invalid, :incomplete_pairs unless pairs.size >= 2 && pairs.flatten.sort == roster
            connection = fixed_team_connection(context: context, lease: lease, session: session)
            rows = connection.tournament_catalog(publication_ref: reference)
            rows = rows.select { |item| item['record']['preview']['membership']['units'].map { |unit| unit['accounts'].sort }.sort == pairs && item['record']['preview']['source']['candidate']['publication_digest'] == RegistrationProjection.publication_generation(publication) }
            if rows.empty? && reference['author'].downcase == @actor.downcase
              intent = 'automatic-pairs-v1:' + Digest::SHA256.hexdigest(JSON.generate([reference, RegistrationProjection.publication_generation(publication), pairs]))
              unless connection.plan_readback(intent_id: intent)
                template = settings['game_options']['team_seats'] || [0, 1, 0, 1]
                preview = connection.plan_preview(publication_ref: reference, pairs: pairs, team_template: template, intent_id: intent)
                connection.plan_accept(preview: preview)
              end
              rows = connection.tournament_catalog(publication_ref: reference).select { |item| item['record']['preview']['intent_id'] == intent }
            end
            if reference['author'].downcase == @actor.downcase
              rows.each do |item|
                connection.plan_dispatch_ensure_configured(intent_id: item['record']['preview']['intent_id'], max_tables: 3)
              end
            end
            roots = rows.map { |item| item['record']['preview']['intent_id'] }
            phase = connection.advance_tournament(publication_ref: reference, root_intents: roots)
            rows = connection.tournament_branch_catalog(publication_ref: reference, root_intents: roots)
            next({state: :confirmed, rows: rows, observed_at: @clock.call, phase_transition: phase}.freeze)
          end
          connection = individual_connection(context: context, lease: lease, session: session)
          rows = connection.tournament_catalog(publication_ref: reference)
          if publication && @clock.call < starts && @clock.call >= publication['registration_closes_at']
            candidate = @service.schedule_candidate(publication_ref: reference).to_h
            # Keep old records for reconciliation, but do not present stale fixtures
            # as the current schedule after a pre-start withdrawal or removal.
            rows = rows.select { |item| item['record']['preview']['source']['candidate']['roster'] == candidate['roster'] && item['record']['preview']['source']['candidate']['publication_digest'] == candidate['publication_digest'] }
          end
          if rows.empty? && reference['author'].downcase == @actor.downcase
            candidate ||= @service.schedule_candidate(publication_ref: reference).to_h
            intent = 'automatic-individual-v2:' + Digest::SHA256.hexdigest(JSON.generate([reference, candidate['roster_generation']]))
            saved = connection.plan_readback(intent_id: intent)
            unless saved
              seats = candidate['matches'].select { |match| match['leg'] == 1 }.to_h { |match| [match['match_id'], match['players']] }
              preview = connection.plan_preview(publication_ref: reference, base_seats: seats, intent_id: intent)
              connection.plan_accept(preview: preview)
            end
            connection.plan_dispatch_configure(intent_id: intent, max_tables: 3)
            rows = connection.tournament_catalog(publication_ref: reference)
            rows = rows.select { |item| item['record']['preview']['source']['candidate']['roster'] == candidate['roster'] && item['record']['preview']['source']['candidate']['publication_digest'] == candidate['publication_digest'] }
          end
          roots = rows.map { |item| item['record']['preview']['intent_id'] }
          phase = connection.advance_tournament(publication_ref: reference, root_intents: roots)
          rows = connection.tournament_branch_catalog(publication_ref: reference, root_intents: roots)
          {state: :confirmed, rows: rows, observed_at: @clock.call, phase_transition: phase}.freeze
        rescue LocalExecutionPlanBackend::Unconfirmed => error
          {state: :uncertain, intent_id: error.intent_id}.freeze
        rescue Publication::Invalid => error
          {state: :blocked, reason: error.code}.freeze
        ensure
          connection&.close(primary: $!)
        end
      end
    end

    def plan_operation(connection_method:, label:, action:, input:, context:, lease:, session:)
      access(label, input: input, plan_input: true, entry_guard: -> { context.current?(lease) }) do |copy|
        connection = nil
        primary = nil
        completed = false
        begin
          connection = public_send(connection_method, context: context, lease: lease, session: session)
          value = case action
          when :preview then connection.plan_preview(**copy.transform_keys(&:to_sym))
          when :accept then connection.plan_accept(preview: copy)
          when :readback then connection.plan_readback(intent_id: copy.fetch('intent_id'))
          when :dispatch_configure then connection.plan_dispatch_configure(**copy.transform_keys(&:to_sym))
          when :organizer_result_status, :organizer_forfeit
            arguments = copy.transform_keys(&:to_sym)
            arguments[:selectors] = arguments.fetch(:selectors).transform_keys(&:to_sym)
            connection.perform(action: action, **arguments).fetch(:operation)
          else raise ArgumentError, 'Nieznana czynność producenta FT1'
          end
          completed = true
          {state: :confirmed, value: value}.freeze
        rescue LocalFixedTeamPlanBackend::Unconfirmed, LocalExecutionPlanBackend::Unconfirmed => error
          completed = true
          {state: :uncertain, intent_id: error.intent_id}.freeze
        rescue Publication::Invalid, CoordinationContract::Blocked => error
          completed = true
          {state: :blocked, reason: error.code}.freeze
        rescue Exception => error
          primary = error
          raise error, cause: error.cause
        ensure
          connection&.close(primary: primary || (completed ? nil : :unwind))
        end
      end
    end

    private

    class AccountChanged < TablesGateway::ContextChanged; end

    def check_account
      current = Data.account(@user.call).downcase
      raise AccountChanged unless current == @owner
    rescue Publication::Invalid
      raise AccountChanged
    end

    def guarded_actor
      check_account
      @actor
    end

    def service_actor
      guarded_actor
    rescue AccountChanged
      raise PublicService::Error, :account_changed
    end

    # Sprawdzenie po I/O nie zasłania pierwotnej awarii, w tym danych
    # UnconfirmedWrite ani błędu programu. Flaga odróżnia starsze $! caller-a.
    def boundary
      check_account
      completed = false
      begin
        result = yield
        completed = true
        result
      ensure
        begin
          check_account
        rescue AccountChanged
          raise if completed
        end
      end
    end

    def compose
      raise @composition_error if @composition_error
      return if @service
      @root ||= boundary { resolve_root(@program.data_path) }
      directory = File.join(@root, 'tournament-local-test-' + Digest::SHA256.hexdigest(@owner))
      actor = method(:guarded_actor)
      clock = -> { boundary { @clock.call } }
      @provider = boundary do
        LocalTestTables.new(directory: File.join(directory, 'tables'), user: actor, clock: clock)
      end
      gateway = TablesGateway.new(server_tables: @provider, user: actor,
        operation_error_classes: [LocalTestTables::Error])
      @journal = boundary do
        OperationJournal.new(directory: File.join(directory, 'journals'), owner: @actor,
          backend_identity: @provider.backend_identity)
      end
      @service = PublicService.new(gateway: gateway, journal: @journal, registry: @registry,
        user: method(:service_actor), backend_identity: @provider.backend_identity, clock: clock)
    rescue *OPERATION_ERRORS => error
      # Niepewny pierwszy dostęp zatrzaskuje kompozycję. Nie pytamy ponownie
      # data_path i nie tworzymy pustego backendu po zmianie cwd/ścieżki.
      @composition_error = error
      raise
    end

    def resolve_root(value)
      unless Data.text?(value) && value.bytesize.between?(1, 4096) &&
          value.match?(/[^[:space:]]/) && !value.match?(/[[:cntrl:]]/)
        raise LocalTestTables::Error, :invalid_directory
      end
      path = value.tr('\\', '/')
      if path.start_with?('//') || path.match?(/\A[A-Za-z]:(?!\/)/)
        raise LocalTestTables::Error, :invalid_directory
      end
      File.expand_path(path).freeze
    end

    def access(title, input: nil, writing: false, entry_guard: nil, plan_input: false)
      return if entry_guard && !entry_guard.call
      check_account
      # Kontrolki mogą zmieniać wejścia podczas pompowania Tasks.run. Kopia
      # powstaje na UI przed startem workera; nie zamraża obiektów caller-a.
      limits = plan_input ? {max_bytes: 1_048_576, max_depth: 16, max_nodes: 65_536} :
        {max_bytes: 262_144, max_depth: 12, max_nodes: 16_384}
      copy = Data.freeze_tree(Data.copy(input, **limits))
      result = boundary do
        EltenAPI::Tasks.run(title: GameRoomContent.utf8(title), ui: :none, cancellable: false) do
          boundary do
            compose
            boundary { yield copy }
          end
        end
      end
      @last_error = nil
      return if entry_guard && !entry_guard.call
      result
    rescue *OPERATION_ERRORS => error
      if entry_guard && !entry_guard.call
        @last_error = error
        return nil
      end
      failure(error, error_message(error, writing: writing))
    end

    # Komunikaty nie cytują payloadu, nazwy konta ani ścieżki. Oryginalny
    # wyjątek z łańcuchem cause zostaje tylko w last_error do diagnostyki.
    def error_message(error, writing:)
      if error.is_a?(TablesGateway::UnconfirmedWrite)
        return uncertain_message
      end
      if error.is_a?(AccountChanged) || (error.is_a?(PublicService::Error) &&
          [:account_changed, :invalid_account, :backend_changed].include?(error.code))
        message = _("The account changed. Close this window and reopen local tournament tests.")
        return writing ? [GameRoomContent.utf8(message), GameRoomContent.utf8(uncertain_message)].join(' ') : message
      end
      if error.is_a?(PublicService::Error)
        return service_message(error.code)
      end
      if error.is_a?(Publication::Invalid)
        return error.code == :local_timezone ?
          _("Local tests require local system time on this computer, not an IANA time zone.") :
          _("The local test publication contains invalid or incomplete settings.")
      end
      return uncertain_message if writing
      causes = []
      source = error
      while source && !causes.include?(source)
        causes << source
        source = source.cause
      end
      if causes.any? { |item| item.is_a?(OperationJournal::Corrupt) ||
          (item.is_a?(LocalTestTables::Error) && [:corrupt_store, :incompatible_schema].include?(item.code)) }
        return _("The local test storage is damaged or incompatible. It has not been replaced.")
      end
      if causes.any? { |item| item.is_a?(StrictJson::IncompatibleRuntime) ||
          (item.respond_to?(:code) && item.code == :incompatible_runtime) }
        return _("This runtime cannot safely read local tournament test data.")
      end
      _("The local test operation could not be completed. Check the operations list before continuing.")
    end

    def uncertain_message
      _("The local test result is uncertain. Check the operations list; do not send again.")
    end

    def service_message(code)
      case code
      when :partner_unavailable
        _("This player already has a partner. Refresh the list and choose a free player.")
      when :invalid_partner
        _("Choose another participant as your partner.")
      when :source_changed
        _("The tournament changed. Refresh its view before changing it again.")
      when :pending_operation
        _("An earlier tournament change is not confirmed. Check Operations before making another change.")
      when :registration_members_outside_window
        _("These registration dates would exclude registered participants. Keep their registration times within the window.")
      when :not_organizer
        _("Only the tournament organizer can change its participants.")
      when :tournament_started
        _("The tournament has started. Withdrawal is no longer available.")
      when :not_registered
        _("You are not registered for this tournament.")
      when :registration_withdrawn
        _("You have withdrawn from this tournament. The previous registration is no longer active.")
      when :not_open
        _("Registration has not opened according to the local computer clock. This is not a server confirmation.")
      when :closed
        _("Registration is closed according to the local computer clock. This is not a server confirmation.")
      when :participant_limit_reached
        _("The tournament participant limit has been reached.")
      when :unknown_tournament, :invalid_tournament_id
        _("The local test tournament was not found. Refresh the list.")
      when :missing_operation, :invalid_operation_id
        _("The local test operation was not found. Reopen the operations list.")
      when :membership_conflict, :ambiguous_intent
        _("Conflicting local test operations were found. Check the operations list; do not send again.")
      when :payload_too_large
        _("The local test publication exceeds the storage limit.")
      when :invalid_clock
        _("The local computer clock cannot be used for this test.")
      else
        _("The local test context is invalid. Close this window and reopen local tournament tests.")
      end
    end

    def failure(error, message)
      @last_error = error
      @alert.call(GameRoomContent.utf8(message))
      nil
    end
  end
end
