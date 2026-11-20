require_relative '../network_errors'
require_relative '../saved_game_save_intent'
require_relative '../tournament_marker'

module GameRoomUseCases
  # A save owns its freeze receipt. Failed persistence or close may release
  # only that boundary; the transport revalidates session and current owner.
  class SaveGame
    def initialize(repository:, transport:, archives:)
      @repository, @transport, @archives = repository, transport, archives
    end

    def reconcile(intent:, id:, game:)
      @archives.call.reconcile(intent: intent, id: id, game: game)
      raise GameRoomSavedGameSaveIntent::ClosePending.new(id)
    end

    def call(table:, table_id:, session:, game:, intent: nil, tournament:nil)
      GameRoomTournamentMarker.ensure_savable!(table, session, tournament: tournament)
      if intent
        return intent.with_save_attempt do
          save(table: table, table_id: table_id, session: session, game: game, intent: intent,tournament:tournament)
        end
      end
      save(table: table, table_id: table_id, session: session, game: game,tournament:tournament)
    end

    private

    def save(table:, table_id:, session:, game:, intent: nil,tournament:nil)
      boundary, attempt = nil, {}
      round_paused = session['__round_pause'] == true
      if intent
        intent.check_context!(owner: table['owner'])
        if intent.for_source(table_id: table_id, session_id: @repository.session_id(session))
          raise GameRoomSavedGameSaveIntent::Pending, 'Existing save requires explicit reconciliation'
        end
      end
      begin
        boundary = round_paused ? @transport.freeze_game(session, round_pause: true) : @transport.freeze_game(session)
        confirmed = @repository.snapshot_for(session, force_events: true)
        raise ArgumentError, 'The room is no longer active' if confirmed == nil
        options = intent ? {intent: intent, boundary: boundary, attempt: attempt} : {}
        options[:tournament]=tournament if tournament
        row = @archives.call.put(game: game, table: table, snapshot: confirmed, repository: @repository,
          now: (confirmed.session['__frozen_at'] || boundary.created_at).to_i, **options)
      rescue StandardError
        @transport.freeze_game(session, frozen: false, expected_boundary: boundary) if boundary && !attempt[:hold_freeze] && !round_paused
        raise
      end
      # deactivate_table has no session/receipt CAS. Never call it for a durable
      # intent, even after readback: confirmation is not permission to close.
      raise GameRoomSavedGameSaveIntent::ClosePending.new(row.fetch('id')) if intent
      begin
        @transport.deactivate_table(table_id: table_id)
      rescue StandardError
        @transport.freeze_game(session, frozen: false, expected_boundary: boundary) unless round_paused
        raise
      end
      true
    end
  end
end
