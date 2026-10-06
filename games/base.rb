require_relative "contracts"
require_relative "../lib/game_surfaces/specifications"
require_relative "../lib/game_session_clock"
require "json"
require_relative "../lib/game_participants"
require_relative "../lib/game_teams"
require_relative "../lib/game_shortcuts"
require_relative "../lib/game_layout_spec"
require_relative "../lib/game_rules"
require_relative "../lib/game_content"
require_relative "../lib/audio_tutorial"
require_relative "../lib/participant_replay"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  # Opt in only when the replay history contains public information. Private
  # hands/answers need their own viewer-aware descriptions. GameScreen already
  # handles turn transitions and the final result, so do not repeat them here.
  module PublicHistoryAnnouncements
    def describe_event(event, repository, replay, _viewer)
      event_id = repository.event_id(event).to_i
      replay.history.to_a.filter_map do |entry|
        next unless entry.event_id.to_i == event_id
        next if [:start, :turn, :result].include?(entry.kind)
        entry.text unless entry.text.to_s.empty?
      end
    end
  end

  class Base
    def self.inherited(game)
      super
      game.prepend(GameRoomParticipantReplay)
    end

    # Optional room services. Games without local services retain the existing
    # lifecycle and never create a service object or perform an extra request.
    # One local client per confirmed game session, including a rematch in the
    # same room. GameScreen closes the previous client before building this one.
    def build_client(_program, **_services); nil; end
    def background_client?; false; end
    def audio_game?; false; end
    # Turn-based model/actions can continue behind another native scene. A
    # realtime client owns its simulation, focus and pause protocol separately.
    def session_runner?; true; end

    # Pure presentation cues from one accepted event. The presenter supplies
    # its event-local history and cosmetic RNG, then owns playback and mixing.
    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      nil
    end

    # A new participant inherits the existing place, never a rewritten event log.
    # Private commitments cannot be reconstructed by a different computer.
    # Games with a private protocol must explicitly opt in at a safe boundary.
    def controller_change_error(replay, replacement: false)
      return _("This game does not support computers.") if replacement && !supports_bots?
      return nil if replay == nil || replay.finished?
      controller_change_phase_error(replay)
    end

    # Replacing one place need not transfer another player's private input.
    # The default remains conservative for existing private-protocol games.
    def participant_replacement_error(replay, player:, replacement: nil)
      controller_change_error(replay, replacement: replacement == nil)
    end

    # Called only for an unfinished game. Models owning private commitments
    # describe their safe boundaries; an unknown realtime model stays closed.
    def controller_change_phase_error(_replay)
      _("Wait until the current game has finished before changing its controller.") unless session_runner?
    end

    # Describe the host-owned settings entry point; models never run its UI.
    def personal_settings_label; nil; end
    def personal_settings_action; nil; end

    # No options means loading defaults. Saving may depend on the selected
    # profile; the model selects definitions, the application owns persistence.
    def remembered_option_definitions(definitions, options: nil)
      definitions.select { |definition| definition.kind.to_s == "multiple_choice" }
    end
    def build_session_game; self.class.new; end
    def build_start_guard(_program, user:, **_services); nil; end
    def supports_leaderboards?; false; end
    def build_leaderboard_client(_program, **_services); nil; end
    def precise_action_clock?; false; end
    def private_table_required?(_options); false; end
    def table_join_error(_options, viewer:, owner:); nil; end
    def join_as_observer?(_options, viewer:, owner:); false; end
    def role_selection_allowed?(_options); true; end
    def table_invitations_allowed?(_options); true; end
    def waiting_view_spec(_viewer, history_empty_label: nil)
      GameRoomLayout::ViewSpec.new(history_empty_label: history_empty_label)
    end
    def room_shortcuts; []; end
    def run_room_command(_program, _command, viewer:, **_services); false; end
    def leave_confirmation(_replay, _viewer, own_table:); nil; end
    def saved_game_requires_private_data?; false; end
    def saved_private_data(_replay, context:); nil; end
    def validate_saved_private_data(_replay, data)
      raise ArgumentError, "Unexpected private save data" unless data == nil
    end
    def restore_private_data(_replay, data, context:)
      validate_saved_private_data(_replay, data)
    end

    PLAYROOM_SUIT_ORDER = %w[H S D C].freeze
    PLAYROOM_RANK_ORDER = %w[2 3 4 5 6 7 8 9 T J Q K A].freeze

    # Headless simulations may override this to extend an already materialized
    # replay with newly appended events. Returning nil keeps the safe generic
    # fallback, which rebuilds the replay from the complete event stream.
    def incremental_replay(_replay, _session, _events, _repository)
      nil
    end

    # A game may opt in when its replay and existing event payloads are
    # immutable during planning. Simulation branches can then share the
    # materialized parent replay until they append their own event instead of
    # serializing the complete history before every search node.
    def shareable_simulation_snapshot?
      false
    end

    def id
      raise NotImplementedError, "a game must implement id"
    end

    def name
      raise NotImplementedError, "a game must implement name"
    end

    def rule_sections
      raise NotImplementedError, "a game must implement rule_sections"
    end

    def audio_tutorial_entries
      []
    end

    def rule_book(options: nil)
      book = GameRoomRules::Book.new(
        game_id: id,
        title: name,
        sections: rule_sections + (supports_bot_move_delay? ? [rule_section(:bot_pacing, GameRoomRules.translate("Time to follow a bot's move"),
          GameRoomRules.translate("Bot move delay lets the table pause briefly before a computer acts, so people can follow the play. Choose 0 to 5 seconds. Zero removes the deliberate pause; it does not disable the bot or change its playing strength. UNO and Makao start at one second, other games at zero."),
          GameRoomRules.translate("The delay belongs to the table and is preserved when a supported game is saved. It does not prevent permitted human actions while waiting. Near a turn deadline the wait is shortened so it cannot keep the bot from acting in time."))] : [])
      )
      return book if options == nil

      book.with_current_options(rules_options_text(normalize_options(options)))
    end

    def minimum_players
      2
    end

    def maximum_players
      2
    end

    # Increment when a rules change makes old event archives incompatible.
    def saved_game_schema_version
      1
    end

    def supports_saved_games?
      true
    end

    # Seconds after the final move during which Restart ignores key presses.
    def restart_guard_seconds
      0
    end

    # Most events use seat numbers or card/square identifiers. Games storing
    # controller names inside values must remap only those documented fields.
    def restored_event_value(event, _controller_mapping)
      event["value"]
    end

    def save_game_error(replay)
      replay.finished? ? _("This game has already finished.") : nil
    end

    def automatic_action(_replay, _actor, context: nil)
      nil
    end

    # Automatic actions are normally authoritative table-master actions. A
    # game may opt individual participants in when the action can only expose
    # their own local state, for example a previously committed answer.
    def automatic_action_allowed?(_replay, actor, table_owner:)
      same_user?(actor, table_owner)
    end

    # Explicit moderation uses the existing authenticated controller route.
    # This never grants an observer the right to make ordinary player moves.
    def moderator_action?(_selection)
      false
    end

    def automatic_actor(replay, viewer, table_owner:)
      same_user?(viewer, table_owner) ? replay.players.first : viewer
    end

    # The game screen uses this pure predicate to wake a form for a deadline.
    # It must not consume randomness or mutate local game state.
    def automatic_action_due?(_replay, _actor, context: nil)
      false
    end

    # Some timed forms need to submit values which still live only in their
    # controls. The screen asks the game for such an action before an
    # authoritative timer transition is allowed to close the phase.
    def automatic_surface_action(_replay, _actor, surface:, context: nil)
      nil
    end

    # Opt in only when a draft can be captured without UI and has an explicit
    # identity. Never reuse a previous round's unsent answers in a new round.
    def automatic_surface_identity(_replay); nil; end

    # Most controls describe one exact position. Simultaneous-input games may
    # keep a choice valid across another player's submission, but must compare
    # its round/phase identity here. action_for still validates the fresh state.
    def concurrent_session_input?(_before, _after, _selection); false; end

    # Timer announcements are local UI cues. A stable key lets the screen say
    # each cue once without writing cosmetic events to the shared game log.
    # Entries contain [key, message, optional_sound_asset].
    def timer_announcements(_replay, _viewer, now: GameRoomClock.now.to_i)
      []
    end

    # nil means that the game has no point score. A scored participant may
    # legitimately have zero (or negative) points; observers have no entry.
    def participant_scores(_replay)
      nil
    end

    # Presentation only: never reorder seats or change the game's scoring.
    # Zero/negative scores do not imply elimination; ties retain seat order.
    def score_announcement_order(units, scores, eliminated: {})
      units.each_with_index.sort_by do |unit, index|
        [eliminated.to_h[unit] ? 1 : 0, -scores[unit].to_i, index]
      end.map(&:first)
    end

    def participant_status(_replay, _participant, connected: true)
      connected ? nil : _("disconnected")
    end

    def active_actors(replay)
      replay.current_player == nil ? [] : [replay.current_player]
    end

    # A local alert for a new decision, not a list of all actors allowed to
    # send an event. Interceptions and automatic reveals must not ring.
    # Simultaneous-input games override this with their public phase/round key.
    def required_decision_key(replay, viewer)
      return nil if replay == nil || replay.finished? || !same_user?(replay.current_player, viewer)

      [turn_phase_kind(replay), viewer.to_s.downcase]
    end

    def legal_actions(_replay, _actor, context: nil)
      []
    end

    # Override only for permanent removal from this match. A lost round,
    # folded hand, passed turn, all-in or disconnection is not elimination.
    def eliminated_from_game?(_replay, _viewer)
      false
    end

    attr_accessor :board_presentation_preferences

    def turn_announcement(replay, viewer)
      return nil if replay == nil || replay.finished? || replay.current_player == nil
      if turn_phase_kind(replay) == :bidding
        return _("You are bidding.") if same_user?(replay.current_player, viewer)

        return _("%{player} is bidding.") % {
          player: participant_name(replay.current_player)
        }
      end
      if turn_phase_kind(replay) == :review
        return _("You are reviewing the answers.") if same_user?(replay.current_player, viewer)

        return _("%{player} is reviewing the answers.") % {
          player: participant_name(replay.current_player)
        }
      end
      if turn_phase_kind(replay) == :choice
        return _("Choose a category.") if same_user?(replay.current_player, viewer)

        return _("%{player} is choosing a category.") % {
          player: participant_name(replay.current_player)
        }
      end
      return _("It is your turn.") if same_user?(replay.current_player, viewer)

      _("It is %{player}'s turn.") % {
        player: participant_name(replay.current_player)
      }
    end

    # Turn changes are derived from accepted game events. They are displayed
    # consistently by GameScreen without creating extra server records, so all
    # sequential games and future Base subclasses receive the same behaviour.
    def turn_transition_history_entry(before_replay, after_replay, event_id:)
      return nil if after_replay == nil || after_replay.finished? || after_replay.current_player == nil

      before_kind = before_replay == nil ? nil : turn_phase_kind(before_replay)
      after_kind = turn_phase_kind(after_replay)
      if before_replay != nil && before_kind == after_kind &&
          same_user?(before_replay.current_player, after_replay.current_player)
        return nil
      end

      player = after_replay.current_player
      text = case after_kind
      when :bidding
        _("%{player} is bidding.") % { player: participant_name(player) }
      when :review
        _("%{player} is reviewing the answers.") % { player: participant_name(player) }
      when :choice
        _("%{player} is choosing a category.") % { player: participant_name(player) }
      else
        _("It is %{player}'s turn.") % { player: participant_name(player) }
      end
      HistoryEntry.new(
        key: "turn:#{event_id.to_i}:#{after_kind}:#{player.to_s.downcase}",
        text: text,
        event_id: event_id.to_i,
        actor: player,
        kind: :turn
      )
    end

    def move_error(status)
      case status
      when :finished
        _("The game has already ended.")
      when :not_your_turn
        _("It is not your turn.")
      when :local_storage_unavailable
        _("Your answer could not be saved on this device and was not sent. Please try again.")
      else
        _("This move is not available.")
      end
    end

    def move_error_for(status, selection: nil, replay: nil, actor: nil)
      move_error(status)
    end

    def replay(_session, _events, _repository)
      raise NotImplementedError, "a game must implement replay"
    end

    def surface_spec(_replay, _viewer)
      raise NotImplementedError, "a game must implement surface_spec"
    end

    def game_view_spec(replay, viewer)
      GameRoomLayout::ViewSpec.new(surface: surface_spec(replay, viewer))
    end

    # Load local, viewer-specific presentation data independently of automatic
    # moves. Never publish it or alter the authoritative replay here.
    def serial_event_presentation?
      false
    end

    def prepare_view(_replay, _viewer, context: nil)
      nil
    end

    # A staged form first persists a small public selection (for example the
    # other party to a negotiation), then asks the game for the local form
    # which completes the action. Games that do not use staged forms keep the
    # default nil result.
    def staged_form_shortcut(_shortcut, _replay, _viewer, _selection)
      nil
    end

    # A game may locally adapt history labels to presentation settings such
    # as board notation. The authoritative replay and server events remain
    # unchanged, so every client can use its own presentation.
    def history_entries_for_display(replay, _viewer, surface_state: {})
      replay.history
    end

    def history_presentation_depends_on_surface_state?
      false
    end

    def game_field_header(_replay, _viewer)
      name
    end

    def action_for(_surface_action, _replay, _actor, context: nil)
      raise NotImplementedError, "a game must implement action_for"
    end

    def describe_event(_event, _repository, _replay, _viewer)
      nil
    end

    # Allows a game to adapt the spoken description to the current surface
    # presentation without changing the stored, canonical history entry.
    def describe_event_for_display(event, repository, replay, viewer, surface_state: {})
      describe_event(event, repository, replay, viewer)
    end

    def result_text(replay)
      if replay.winner != nil
        return _("%{player} won the game.") % { player: participant_name(replay.winner) }
      end
      return _("The game ended in a draw.") if replay.draw

      nil
    end

    protected

    def rule_section(id, title, *paragraphs)
      GameRoomRules::Section.new(id: id, title: title, paragraphs: paragraphs)
    end

    def canonical_json(value)
      JSON.generate(canonical_value(value))
    end

    # Standard Playroom hand order: group cards by suit, then expose each suit
    # from its lowest rank to its highest rank. Games with duplicate decks may
    # provide a final stable key without changing the visible rank order.
    def playroom_hand_sort_key(card, ranks: PLAYROOM_RANK_ORDER, suits: PLAYROOM_SUIT_ORDER, tie_breaker: 0)
      suit_index = suits.index(card_suit(card))
      rank_index = ranks.index(card_rank(card))
      [
        suit_index == nil ? suits.length : suit_index,
        rank_index == nil ? ranks.length : rank_index,
        tie_breaker
      ]
    end

    def standard_hand_sort_keys(rank:, suit:, position:)
      suit_index = PLAYROOM_SUIT_ORDER.index(suit) || PLAYROOM_SUIT_ORDER.length
      rank_index = PLAYROOM_RANK_ORDER.index(rank) || PLAYROOM_RANK_ORDER.length
      { "colour" => [suit_index, rank_index], "number" => [rank_index, suit_index], "none" => [position] }
    end

    def canonical_value(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
          source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
          result[key] = canonical_value(value[source_key])
        end
      when Array
        value.map { |item| canonical_value(item) }
      when Symbol
        value.to_s
      else
        value
      end
    end

    def current_turn_shortcut_text(replay, viewer)
      return result_text(replay) || _("The game is finished.") if replay.finished?
      return _("There is no active turn.") if replay.current_player == nil

      turn_announcement(replay, viewer)
    end

    def turn_phase_kind(replay)
      phase = replay&.state.is_a?(Hash) ? replay.state[:phase].to_s.to_sym : nil
      return :bidding if [:bidding, :auction].include?(phase)
      return :review if [:review, :judging].include?(phase)
      return :choice if [:choosing].include?(phase)

      :turn
    end

    def event_plan(action, value)
      ActionPlan.single(action: action, value: value)
    end

    def starting_history(players)
      text = if players.length == 2
        _("Game started: %{first} versus %{second}.") % {
          first: participant_name(players[0]),
          second: participant_name(players[1])
        }
      else
        _("Game started: %{players}.") % {
          players: players.map { |player| participant_name(player) }.join(", ")
        }
      end
      HistoryEntry.new(
        key: "start",
        text: text,
        event_id: 0,
        actor: "",
        kind: :start
      )
    end

    def result_history(event_id:, winner: nil, draw: false)
      if winner != nil
        HistoryEntry.new(
          key: "result:#{event_id}",
          text: _("%{player} won the game.") % { player: participant_name(winner) },
          event_id: event_id,
          actor: winner,
          kind: :result
        )
      elsif draw
        HistoryEntry.new(
          key: "result:#{event_id}",
          text: _("The game ended in a draw."),
          event_id: event_id,
          actor: "",
          kind: :result
        )
      end
    end

    def field_label(column, row)
      "#{(65 + column.to_i).chr}#{row.to_i + 1}"
    end

    def player_index(players, actor)
      players.index { |player| same_user?(player, actor) }
    end

    def other_player(players, actor)
      players.find { |player| !same_user?(player, actor) }
    end

    def same_user?(first, second)
      GameRoomParticipants.same?(first, second)
    end

    def participant_name(participant)
      GameRoomParticipants.display_name(participant)
    end

    def selection_value(selection, key)
      return selection[key].to_i if selection.respond_to?(:key?) && selection.key?(key)
      symbol = key.to_sym
      return selection[symbol].to_i if selection.respond_to?(:key?) && selection.key?(symbol)

      0
    end
  end
end

require_relative "base/options"

require_relative "base/teams"

require_relative "base/bots"

require_relative "base/shortcuts"
