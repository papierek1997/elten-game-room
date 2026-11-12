class GameRoomLiveSessionStore
  # Owned by the store mutex. A room is evicted as one generation, so no
  # parallel cache can survive its records or be reused by an old callback.
  class RoomState
    attr_accessor :records, :record_keys, :message_records, :pending_move,
      :recovered_moves, :stack_cursor, :received_sequences, :private_game_messages,
      :record_generation, :validated_records, :control_lock, :attachment, :ownership_token,
      :io_count, :subscription_count, :public_game_previews, :private_draws, :verified_pools, :shared_draws, :shared_draw_lock,
      :game_projection, :control_projection, :history_corrections,
      :compacted_game_through, :compacted_game_id, :compacted_archive_id
    attr_reader :clock_revisions, :resource_id

    def initialize
      @records, @recovered_moves, @private_game_messages = [], [], []
      @public_game_previews = []
      @private_draws, @verified_pools = {}, {}
      @shared_draws = {}
      @shared_draw_lock = Mutex.new
      @record_keys, @message_records, @received_sequences = {}, {}, {}
      @clock_revisions = Hash.new(0)
      @ownership_token = Object.new
      @stack_cursor = @record_generation = @io_count = @subscription_count = 0
      @history_corrections = 0
      @compacted_game_through = 0
    end

    def retained?
      @pending_move || @io_count.positive? || @subscription_count.positive? ||
        !@recovered_moves.empty? || !@private_game_messages.empty? || @control_lock&.locked?
    end

    # A fresh native membership may rejoin this resource, but a coincident
    # application table number does not authorize reusing another UUID's log.
    def bind_resource!(native_id)
      if @resource_id && @resource_id != native_id
        raise GameRoomLiveSessionStore::ResourceConflict, 'The table connection changed'
      end
      @resource_id ||= native_id.dup.freeze
    end

    def take_recovered_moves
      result, @recovered_moves = @recovered_moves, []
      result
    end

    def take_private_game_messages
      result, @private_game_messages = @private_game_messages, []
      result
    end

    def take_public_game_previews
      result, @public_game_previews = @public_game_previews, []
      result
    end

    # Only obsolete game payloads are retired. Room/chat/control metadata and
    # the current import remain available, including after a late callback.
    def compacted_game_record?(record)
      return false unless record.sequence <= @compacted_game_through
      data = record.packet['data']
      case record.packet['kind']
      when 'game_action' then data['session_id'] != @compacted_game_id
      when 'game_archive' then data['archive_id'] != @compacted_archive_id
      else false
      end
    end
  end

  private

  def room_state(table_id)
    @rooms[table_id] ||= RoomState.new
  end
end
