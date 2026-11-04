require "securerandom"
require_relative "game_room_localization"
require_relative "game_participants"
require_relative "game_snapshot"

module GameRoomUI
  # Only controls owned by the still displayed table receive this gate. Cursor
  # movement and editing remain native; activation must not prepare a second
  # move before the first request has an authoritative outcome.
  module ActivationGate
    attr_accessor :game_room_activation_guard

    def trigger(event, *arguments)
      if [:select, :press].include?(event) && game_room_activation_guard
        return unless game_room_activation_guard.call
      end
      super
    end
  end

  class PendingOperation
    using GameRoomLocalization::Translations
    attr_reader :form, :table_id, :session_id, :view_generation, :input_mode

    LOCAL_COMMANDS = %w[
      sort_cards navigate_playable_card navigate_playable_tile announce_packet
      toggle_orientation toggle_coordinate_labels toggle_player_labels
      announce_moves navigate_piece announce_square_details announce_dice
      show_categories word_rack word_read word_sort word_preview meld_read
      scores server position effects echo crowd perspective_first perspective_second
      perspective_third perspective_fourth
      tile_table tile_side meld_table open_menu
    ].freeze

    def initialize(layout:, table_id:, session_id:, token:, title:, clock: nil, chat_admission: false, local_input: nil, move_admission: nil)
      @layout, @form = layout, layout.form
      raise ArgumentError, "a table operation is already pending" if @form.game_room_pending_operation
      @table_id, @session_id, @token, @title = table_id, session_id, token, title
      @view_generation = layout.binding_generation
      @input_mode = :navigation
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @started_at = @clock.call
      @previous_background_help = @form.game_room_background_help_enabled
      @form.game_room_background_help_enabled = true
      @form.game_room_pending_operation = self
      @guard = method(:reject_action)
      @controls = @form.fields.dup
      @controls.each { |field| field.extend(ActivationGate) unless field.is_a?(ActivationGate) }
      @previous_guards = @controls.map(&:game_room_activation_guard)
      @controls.each { |field| field.game_room_activation_guard = @guard }
      @move_admission = move_admission
      if @move_admission
        @move_guard = -> { admits_move? || reject_action }
        layout.surface&.fields.to_a.each { |field| field.game_room_activation_guard = @move_guard }
      end
      # Admission records a bounded send intention; it does not start another
      # request inside Tasks.run. The chat handler still rejects /move here.
      if chat_admission && layout.respond_to?(:chat)
        @chat_guard = -> { active? }
        layout.chat.game_room_activation_guard = @chat_guard
      end
      @surface = layout.surface
      @previous_surface_guard = @surface.action_guard if @surface.respond_to?(:action_guard)
      @surface_guard = if local_input || @move_admission
        -> { active? && (local_input&.call(@surface) || admits_move?) || reject_action }
      else
        @guard
      end
      @surface.action_guard = @surface_guard if @surface.respond_to?(:action_guard=)
    end

    def active?
      !@closed && @form.game_room_pending_operation.equal?(self) &&
        @layout.binding_generation == @view_generation && @layout.session_id == @session_id
    end

    def safe_shortcut?(shortcut)
      [:announcement, :browse].include?(shortcut.kind) ||
        (shortcut.kind == :surface && LOCAL_COMMANDS.include?(shortcut.action_name.to_s))
    end

    def admits_move?
      active? && @move_admission && @move_admission.call
    end

    def reject_action
      now = @clock.call
      if active? && (!@last_notice || now - @last_notice >= 2.0)
        @last_notice = now
        @form.__send__(:speak, GameRoomContent.utf8(_("Please wait...")))
      end
      false
    end

    def update
      unless active?
        @token.cancel(EltenAPI::Tasks::Cancelled.new("Table view changed"))
        return
      end
      if !@form.game_room_background_help? && @form.__send__(:key_pressed?, :key_escape)
        @token.cancel(EltenAPI::Tasks::Cancelled.new("Task cancelled"))
        @form.__send__(:clear_game_room_key)
        return
      end
      if !@announced && @clock.call - @started_at >= 5.0
        @announced = true
        reject_action
      end
      @form.update
    end

    def close
      return if @closed
      @closed = true
      @controls.each_with_index do |field, index|
        if [@guard, @chat_guard, @move_guard].compact.any? { |guard| field.game_room_activation_guard.equal?(guard) }
          field.game_room_activation_guard = @previous_guards[index]
        end
      end
      if @surface.respond_to?(:action_guard) && @surface.action_guard.equal?(@surface_guard)
        @surface.action_guard = @previous_surface_guard
      end
      if @form.game_room_pending_operation.equal?(self)
        @form.game_room_pending_operation = nil
        @form.game_room_background_help_enabled = @previous_background_help
      end
    end
  end

  # A small UI-owned buffer for explicit roster commands, not a second writer.
  # The ordinary room command checks fresh permissions/capacity before each
  # write. No command survives a match, owner, account or membership change.
  class ComputerChangeBuffer
    LIMIT = 8

    def initialize
      clear
    end

    def enqueue(action, participant = nil, **context)
      return false unless [:add_bot, :remove_bot].include?(action)
      return false if action == :remove_bot && !GameRoomParticipants.bot?(participant)
      clear unless current?(**context)
      return false unless GameRoomParticipants.same?(context[:actor], context[:owner])
      @context ||= context.merge(actor: context[:actor].to_s.dup.freeze,
        owner: context[:owner].to_s.dup.freeze).freeze
      # Holding Delete must not remove the next row after this person leaves.
      return true if action == :remove_bot && @commands.any? { |item| item == [action, participant] }
      return false if @commands.length >= LIMIT

      @commands << [action, participant&.dup&.freeze].freeze
      true
    end

    def take(**context)
      clear unless current?(**context)
      @commands.shift
    end

    def removed(participant, before:, after:)
      survivors = before.reject { |bot| bot == participant }
      names = ->(bots) { bots.map { |bot| GameRoomParticipants.bot_name_token(bot) } }
      unless survivors.length == before.length - 1 && after.length == survivors.length &&
          names.call(survivors) == names.call(after)
        clear
        return
      end
      # Waiting rooms compact numbered slots. Rebase only this acknowledged
      # removal, not an arbitrary later lookup by name: a newly added computer
      # can reuse a removed name and must not inherit that person's Delete.
      mapping = survivors.zip(after).to_h
      @commands = @commands.filter_map do |action, target|
        next [action, target].freeze unless action == :remove_bot
        replacement = mapping[target]
        [action, replacement.dup.freeze].freeze if replacement
      end
    end

    def clear
      @commands = []
      @context = nil
    end

    private

    def current?(table_id:, session_id:, actor:, membership:, owner:, ownership: nil)
      @context && @context[:table_id] == table_id && @context[:session_id] == session_id &&
        @context[:membership].equal?(membership) &&
        @context[:ownership].equal?(ownership) &&
        GameRoomParticipants.same?(@context[:actor], actor) &&
        GameRoomParticipants.same?(@context[:owner], owner) &&
        GameRoomParticipants.same?(owner, actor)
    end
  end

  # Identity and edit generation, not text equality alone: deleting a sent
  # draft and typing the same words again creates a different draft.
  ChatSubmission = Struct.new(:control, :generation, :session_id, :text, keyword_init: true) do
    def self.capture(control, session_id:)
      receipt = new(control: control, generation: control.game_room_edit_generation,
        session_id: session_id, text: control.text.to_s.dup.freeze).freeze
      control.game_room_track_submission(receipt)
      receipt
    end

    def same_draft?(other)
      other && control.equal?(other.control) && generation == other.generation && session_id == other.session_id
    end

    def clear_if_current(current_control, session_id:)
      return false unless current_control.equal?(control) && self.session_id == session_id

      remaining = generation == control.game_room_edit_generation ? "" : control.game_room_submission_tail(self)
      return false if remaining.nil?

      index, check = [control.index, control.check].map { |position| [[position.to_i - text.length, 0].max, remaining.length].min }
      control.set_text(remaining)
      control.index, control.check = index, check
      true
    end
  end

  # UI-owned, bounded admission, shared by the waiting room and game screen.
  # It never writes or retries by itself. The ordinary task/writer drains one
  # intention after the current operation; another draft may wait behind it.
  class ChatSendBuffer
    Intent = Struct.new(:receipt, :message, :table, :actor, :message_id, :membership, keyword_init: true) do
      def current?(table_id:, session_id:, actor:, membership:)
        (table['__id'] || table['id']).to_i == table_id.to_i &&
          receipt.session_id == session_id && GameRoomParticipants.same?(self.actor, actor) &&
          self.membership.equal?(membership)
      end

      def write_options
        {message_id: message_id, expected_session_id: receipt.session_id,
          expected_membership: membership}
      end
    end

    def enqueue(control, message:, session_id:, table:, actor:, membership:)
      receipt = ChatSubmission.capture(control, session_id: session_id)
      return :duplicate if [@pending, @sending].compact.any? { |intent| intent.receipt.same_draft?(receipt) }
      return :full if @pending

      context = {table_id: (table['__id'] || table['id']).to_i, session_id: session_id, actor: actor, membership: membership}
      @pending = if @failed && @failed.receipt.same_draft?(receipt) && @failed.current?(**context)
        @failed
      else
        # Do not capture native discovery objects, whose runtime is not owned
        # by this draft. These are the fields needed by the activity writer.
        own_table = GameRoomSnapshot.copy(table.slice('__id', 'id', 'owner', '__insertion_user',
          'game', '__live_session_id', 'private')).freeze
        Intent.new(receipt: receipt, message: message.to_s.dup.freeze, table: own_table,
          actor: actor.to_s.dup.freeze, message_id: SecureRandom.uuid.freeze, membership: membership).freeze
      end
      :queued
    end

    def pending?(**context)
      @pending = nil if @pending && !@pending.current?(**context)
      @pending != nil
    end

    def take(**context)
      return unless pending?(**context)
      @sending, @pending = @pending, nil
      @sending
    end

    def complete(intent, success:)
      return unless @sending.equal?(intent)
      @failed = success ? nil : intent
      @sending = nil
    end

    def clear
      @pending = @sending = @failed = nil
    end
  end
end
