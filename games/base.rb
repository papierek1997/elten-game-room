require "json"
require_relative "../lib/game_participants"
require_relative "../lib/game_teams"
require_relative "../lib/game_shortcuts"
require_relative "../lib/game_layout"
require_relative "../lib/game_rules"
require_relative "../lib/game_content"

module GameRoomGames
  EventCommand = Struct.new(:action, :value, keyword_init: true)

  # Untranslated text from a packaged app can retain ASCII-8BIT even when
  # its bytes are UTF-8. Host controls append their own translated labels.
  OptionChoice = Struct.new(:value, :label, keyword_init: true) do
    def initialize(**attributes)
      super(**attributes.merge(label: GameRoomContent.utf8(attributes[:label])))
    end
  end
  ShortcutChoice = Struct.new(:value, :label, keyword_init: true)
  OptionDefinition = Struct.new(
    :key,
    :label,
    :kind,
    :default,
    :choices,
    :visible_if,
    keyword_init: true
  ) do
    def initialize(**attributes)
      super(**attributes.merge(label: GameRoomContent.utf8(attributes[:label])))
    end
  end

  ActionPlan = Struct.new(:events, keyword_init: true) do
    def self.single(action:, value:)
      new(events: [EventCommand.new(action: action.to_s, value: value.to_s)])
    end
  end

  ActionContext = Struct.new(
    :session_id,
    :table_id,
    :hidden_submissions,
    :random_source,
    :now,
    :options,
    :table_owner,
    :local_data,
    keyword_init: true
  )

  GameShortcut = Struct.new(
    :key,
    :modifiers,
    :label,
    :kind,
    :message,
    :prompt,
    :action_kind,
    :action_name,
    :value_key,
    :allowed_values,
    :default_value,
    :invalid_message,
    :payload,
    :choices,
    :fields,
    keyword_init: true
  ) do
    KINDS = [:announcement, :browse, :number_input, :choice, :staged_form, :form, :action, :surface].freeze
    NAMED_KEYS = ["space", "delete", "backspace"].freeze

    def initialize(
      key:,
      modifiers: nil,
      label:,
      kind:,
      message: nil,
      prompt: nil,
      action_kind: nil,
      action_name: nil,
      value_key: nil,
      allowed_values: nil,
      default_value: nil,
      invalid_message: nil,
      payload: nil,
      choices: nil,
      fields: nil
    )
      normalized_key = key.to_s.downcase
      normalized_modifiers = modifiers.to_a.map(&:to_sym).uniq.sort
      supported_modifiers = [:alt, :control, :shift]
      if normalized_modifiers.any? { |modifier| !supported_modifiers.include?(modifier) }
        raise ArgumentError, "a game shortcut contains an unsupported modifier"
      end
      normalized_kind = kind.to_sym
      if !/\A[a-z0-9]\z/.match?(normalized_key) && !NAMED_KEYS.include?(normalized_key)
        raise ArgumentError, "a game shortcut requires one letter, digit or supported named key"
      end
      raise ArgumentError, "unsupported game shortcut kind" if !KINDS.include?(normalized_kind)
      raise ArgumentError, "a game shortcut requires a label" if label.to_s.empty?
      if normalized_kind == :announcement
        raise ArgumentError, "an announcement shortcut requires a message" if message.to_s.empty?
      elsif normalized_kind == :form
        raise ArgumentError, "a form shortcut requires fields and an action" if fields.to_a.empty? || action_kind.to_s.empty? || action_name.to_s.empty?
        raise ArgumentError, "invalid form field" if fields.any? { |field| !field.is_a?(OptionDefinition) || ![:integer, :choice, :multiple_choice, :boolean].include?(field.kind.to_sym) }
      elsif normalized_kind == :number_input
        raise ArgumentError, "a number shortcut requires a prompt" if prompt.to_s.empty?
        raise ArgumentError, "a number shortcut requires an action" if action_kind.to_s.empty? || action_name.to_s.empty?
        raise ArgumentError, "a number shortcut requires a payload key" if value_key.to_s.empty?
        if allowed_values.is_a?(Range)
          first, last = allowed_values.begin, allowed_values.end
          raise ArgumentError, "invalid numeric range" if !first.is_a?(Integer) || !last.is_a?(Integer) || allowed_values.exclude_end? || first > last
        else
          values = allowed_values.to_a.map(&:to_i).uniq.sort
          raise ArgumentError, "a number shortcut requires allowed values" if values.empty?
          allowed_values = values
        end
      elsif [:browse, :choice, :staged_form].include?(normalized_kind)
        raise ArgumentError, "a choice shortcut requires a prompt" if prompt.to_s.empty?
        if [:choice, :staged_form].include?(normalized_kind)
          raise ArgumentError, "a choice shortcut requires an action" if action_kind.to_s.empty? || action_name.to_s.empty?
          raise ArgumentError, "a choice shortcut requires a payload key" if value_key.to_s.empty?
        end
        choices = choices.to_a.map do |choice|
          if choice.respond_to?(:value) && choice.respond_to?(:label)
            ShortcutChoice.new(value: choice.value, label: choice.label.to_s)
          elsif choice.respond_to?(:key?)
            value = choice.key?(:value) ? choice[:value] : choice["value"]
            label = choice.key?(:label) ? choice[:label] : choice["label"]
            ShortcutChoice.new(value: value, label: label.to_s)
          else
            values = choice.to_a
            ShortcutChoice.new(value: values[0], label: values[1].to_s)
          end
        end
        if choices.empty? || choices.any? { |choice| choice.label.empty? }
          raise ArgumentError, "a choice shortcut requires labelled choices"
        end
      else
        raise ArgumentError, "an action shortcut requires an action" if action_kind.to_s.empty? || action_name.to_s.empty?
        raise ArgumentError, "an action shortcut payload must be a hash" if payload != nil && !payload.respond_to?(:to_h)
      end

      super(
        key: normalized_key,
        modifiers: normalized_modifiers,
        label: label.to_s,
        kind: normalized_kind,
        message: message == nil ? nil : message.to_s,
        prompt: prompt == nil ? nil : prompt.to_s,
        action_kind: action_kind == nil ? nil : action_kind.to_s,
        action_name: action_name == nil ? nil : action_name.to_s,
        value_key: value_key == nil ? nil : value_key.to_s,
        allowed_values: allowed_values,
        default_value: default_value,
        invalid_message: invalid_message == nil ? nil : invalid_message.to_s,
        payload: payload == nil ? {} : payload.to_h,
        choices: choices,
        fields: fields
      )
    end

    def allowed_value?(value)
      return false if kind != :number_input

      allowed_values.include?(Integer(value.to_s, 10))
    rescue ArgumentError
      false
    end
  end

  HistoryEntry = Struct.new(
    :key,
    :text,
    :event_id,
    :actor,
    :kind,
    :field,
    :value,
    keyword_init: true
  )

  Replay = Struct.new(
    :board,
    :players,
    :current_player,
    :winner,
    :draw,
    :accepted_events,
    :history,
    :state,
    keyword_init: true
  ) do
    def finished?
      winner != nil || draw == true
    end
  end

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

    def rule_book(options: nil)
      book = GameRoomRules::Book.new(
        game_id: id,
        title: name,
        sections: rule_sections + (supports_bots? ? [rule_section(:bot_pacing, GameRoomRules.translate("Time to follow a bot's move"),
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

    def supports_bots?
      false
    end

    def option_definitions
      []
    end

    def content_pack_kind
      nil
    end

    # Word games with one dictionary/deck per language do not need a redundant
    # one-item set picker. Quiz keeps its existing independent set selector.
    def single_content_set?
      false
    end

    def content_registry
      GameRoomContent.registry
    end

    def effective_option_definitions(selected = {})
      definitions = content_option_definitions(selected) + option_definitions.to_a
      if supports_bots?
        definitions << OptionDefinition.new(key: "bot_delay", label: _("Bot move delay in seconds (0 to 5); zero disables the pause"), kind: :integer, default: default_bot_move_delay)
      end
      keys = definitions.map { |definition| definition.key.to_s }
      raise ArgumentError, "game option keys must be unique" if keys.uniq.length != keys.length

      definitions
    end

    def default_options
      normalize_options({})
    end

    def new_game_options(values)
      normalize_options(values)
    end

    # Games declare dependencies between options, while the shared table
    # configuration form owns hiding and showing the corresponding controls.
    # A hash requires every named option to match. A callable can express a
    # compound condition without putting game-specific branches in the UI.
    def option_visible?(definition, values, normalize: true)
      condition = definition.visible_if
      return true if condition == nil

      options = normalize ? normalize_options(values) : values
      return condition.call(options) == true if condition.respond_to?(:call)
      return false if !condition.respond_to?(:all?)

      condition.all? do |key, expected|
        actual = options[key.to_s]
        expected.respond_to?(:call) ? expected.call(actual) == true : Array(expected).include?(actual)
      end
    end

    def normalize_options(values)
      source = values.is_a?(Hash) ? values : {}
      result = effective_option_definitions.each_with_object({}) do |definition, normalized|
        key = definition.key.to_s
        raw = if source.key?(key)
          source[key]
        elsif source.key?(key.to_sym)
          source[key.to_sym]
        else
          definition.default
        end
        normalized[key] = normalize_option_value(definition, raw)
      end
      team_seats = source[GameRoomTeams::OPTION_KEY] || source[GameRoomTeams::OPTION_KEY.to_sym]
      result[GameRoomTeams::OPTION_KEY] = team_seats.to_a.map(&:to_i) if team_seats.is_a?(Array)
      normalize_content_options(source, result)
      result
    end

    def options_from_json(value)
      parsed = value.to_s.empty? ? {} : JSON.parse(value.to_s)
      normalize_options(parsed)
    rescue JSON::ParserError
      default_options
    end

    def options_error(_options, player_count: nil)
      nil
    end

    # A variant may change a dependent default in the editor, but must retain
    # a value which the user has already customized. Replay never calls this.
    def option_editor_changes(_previous, _current)
      {}
    end

    def validation_error(options, player_count: nil)
      content_options_error(options) || bot_delay_options_error(options) || options_error(options, player_count: player_count)
    end

    def default_bot_move_delay; 0; end

    def bot_delay_options_error(options)
      return nil unless supports_bots?
      values = normalize_options(options)
      return _("Bot move delay must be from 0 to 5 seconds.") unless values["bot_delay"].between?(0, 5)
      limits = %w[thinking_time answer_time round_time auction_decision_time].filter_map do |key|
        value = values[key].to_i
        value if value > 0
      end
      return _("Bot move delay cannot exceed thinking time.") if limits.any? { |limit| values["bot_delay"] > limit }
      nil
    end

    def options_summary(_options)
      ""
    end

    def combined_options_summary(options)
      parts = [content_options_summary(options), options_summary(options)]
        .map { |part| part.to_s.strip }
        .reject(&:empty?)
      parts.join("; ")
    end

    def rules_option_visible?(definition, options)
      option_visible?(definition, options, normalize: false)
    end

    # Read-only snapshot of the effective settings, not the abbreviated lobby
    # summary. Disabled and inapplicable additions are intentionally omitted.
    def rules_options_text(options)
      lines = effective_option_definitions.filter_map do |definition|
        next if !rules_option_visible?(definition, options)
        value = options[definition.key.to_s]
        case definition.kind.to_sym
        when :boolean
          definition.label if value == true
        when :choice
          choice = definition.choices.to_a.find { |item| item.value.to_s == value.to_s }
          "#{definition.label}: #{choice ? choice.label : value}"
        when :multiple_choice
          selected = definition.choices.to_a.each_with_index.filter_map do |choice, index|
            choice.label if (value.to_i & (1 << index)) != 0
          end
          "#{definition.label}: #{selected.join(', ')}" if !selected.empty?
        else
          "#{definition.label}: #{value}"
        end
      end
      seats = options[GameRoomTeams::OPTION_KEY]
      if seats.is_a?(Array) && options["team_size"].to_i > 0
        lines << (_("Teams in seating order: %{teams}") % { teams: seats.map { |team| team.to_i + 1 }.join(", ") })
      end
      lines.empty? ? _("This table uses fixed rules with no configurable additions.") : lines.join("\r\n\r\n")
    end

    def table_options_announcement(options)
      "#{name}. #{rules_options_text(normalize_options(options)).gsub(/\r?\n+/, '. ')}"
    end

    # Increment when a rules change makes old event archives incompatible.
    def saved_game_schema_version
      1
    end

    def supports_saved_games?
      true
    end

    # Most events use seat numbers or card/square identifiers. Games storing
    # controller names inside values must remap only those documented fields.
    def restored_event_value(event, _controller_mapping)
      event["value"]
    end

    def save_game_error(replay)
      replay.finished? ? _("This game has already finished.") : nil
    end

    def selected_content_pack(options)
      return nil if content_pack_kind.to_s.empty?

      normalized = normalize_options(options)
      pack = content_registry.pack(normalized[GameRoomContent::PACK_OPTION_KEY])
      return nil if pack == nil || !pack.supports?(game_id: id, kind: content_pack_kind)
      return nil if pack.set_id != normalized[GameRoomContent::SET_OPTION_KEY].to_s
      return nil if pack.language_id != normalized[GameRoomContent::LANGUAGE_OPTION_KEY].to_s
      return nil if pack.version != normalized[GameRoomContent::PACK_VERSION_KEY].to_i
      return nil if pack.checksum != normalized[GameRoomContent::PACK_CHECKSUM_KEY].to_s.downcase

      pack
    end

    def team_size(_options, player_count:)
      0
    end

    def team_assignment(options, players:)
      participants = GameRoomParticipants.unique(players)
      size = team_size(options, player_count: participants.length).to_i
      return nil if size <= 0

      normalized = normalize_options(options)
      GameRoomTeams::Assignment.new(
        players: participants,
        team_size: size,
        seats: normalized[GameRoomTeams::OPTION_KEY]
      )
    rescue ArgumentError
      nil
    end

    def with_team_assignment(options, players:, seats:)
      normalized = normalize_options(options)
      assignment = GameRoomTeams::Assignment.new(
        players: players,
        team_size: team_size(normalized, player_count: players.length),
        seats: seats
      )
      error = assignment.validation_error
      raise ArgumentError, error if error != nil

      normalized.merge(GameRoomTeams::OPTION_KEY => assignment.seats.dup)
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
      !GameRoomParticipants.includes?(replay.players, viewer) && same_user?(viewer,table_owner) ? replay.players.first : viewer
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

    # Timer announcements are local UI cues. A stable key lets the screen say
    # each cue once without writing cosmetic events to the shared game log.
    def timer_announcements(_replay, _viewer, now: Time.now.to_i)
      []
    end

    # nil means that the game has no point score. A scored participant may
    # legitimately have zero (or negative) points; observers have no entry.
    def participant_scores(_replay)
      nil
    end

    def participant_status(_replay, _participant, connected: true)
      connected ? nil : _("disconnected")
    end

    def active_actors(replay)
      replay.current_player == nil ? [] : [replay.current_player]
    end

    def legal_actions(_replay, _actor, context: nil)
      []
    end

    def bot_observation(_replay, _actor)
      replay = _replay
      {
        "board" => replay.board,
        "players" => replay.players,
        "current_player" => replay.current_player,
        "winner" => replay.winner,
        "draw" => replay.draw == true,
        "events" => replay.accepted_events.to_a.map do |event|
          {
            "actor" => event["actor"].to_s,
            "action" => event["action"].to_s,
            "value" => event["value"].to_s
          }
        end
      }
    end

    # Games with private hands or answers must return false and provide a safe
    # bot_observation. Tree search then falls back to a non-cheating strategy.
    def perfect_information?
      true
    end

    # Optional local pacing; human actions and network synchronization do not wait.
    def bot_move_delay(replay, _actor, context: nil)
      options = context&.options || replay.state[:options] || {}
      delay = [[normalize_options(options)["bot_delay"].to_f, 0.0].max, 5.0].min
      state = replay.state
      deadline = state[:turn_deadline].to_f
      deadline = state[:deadline].to_f if state[:phase] == :answering
      deadline = state[:auction_deadline].to_f if state[:phase] == :auction
      if deadline > 0
        now = context&.now || Time.now.to_f
        delay = [delay, [deadline - now.to_f - 1.0, 0.0].max].min
      end
      delay
    end

    # This key controls only the local waiting period, never submission or
    # confirmation. Games may ignore events that leave the pending turn intact.
    def bot_delay_revision(_replay, revision)
      revision
    end

    # Opt in only for games with simultaneous or out-of-turn actions.
    # Their normal action_for/replay validation still decides legality.
    def actions_during_bot_turn?
      false
    end

    def bot_action_score(_replay, _actor, _action, context: nil)
      0.0
    end

    def bot_state_key(replay, actor)
      aliases = replay.players.each_with_index.each_with_object({}) do |(player, index), result|
        result[player.to_s.downcase] = same_user?(player, actor) ? "self" : "player:#{index + 1}"
      end
      canonical_json(bot_identity_value(bot_observation(replay, actor), aliases))
    end

    # Search-based games may override this with a compact board encoding.
    def bot_search_key(replay, actor)
      bot_state_key(replay, actor)
    end

    def bot_action_key(action)
      canonical_json(action)
    end

    def bot_allied?(_replay, first, second)
      same_user?(first, second)
    end

    def bot_reward(replay, actor)
      return 0.0 if !replay.finished? || replay.draw
      return 1.0 if same_user?(replay.winner, actor)

      -1.0
    end

    def bot_position_value(replay, actor)
      replay.finished? ? bot_reward(replay, actor) : 0.0
    end

    # Override only for permanent removal from this match. A lost round,
    # folded hand, passed turn, all-in or disconnection is not elimination.
    def eliminated_from_game?(_replay, _viewer)
      false
    end

    def shortcut_features
      [:turn, :material]
    end

    # Board games supply counts from the current replay, never from a cached
    # score or from the initial position. Unsupported games expose no shortcut.
    def remaining_piece_counts(_replay)
      nil
    end

    def shortcut_feature_data(feature, replay, viewer)
      case feature.to_sym
      when :turn
        message = current_turn_shortcut_text(replay, viewer)
        message.to_s.empty? ? nil : { message: message }
      when :material
        counts = remaining_piece_counts(replay)
        return nil if counts == nil

        message = replay.players.each_with_index.map do |player, index|
          _("%{player}: %{pieces}") % { player: participant_name(player), pieces: counts.fetch(index) }
        end.join("; ")
        { message: message }
      else
        nil
      end
    end

    def table_cards_browse_data(state)
      plays = state[:current_trick].to_a
      choices = if plays.empty?
        [
          ShortcutChoice.new(
            value: nil,
            label: _("No cards have been played in this trick")
          )
        ]
      else
        plays.map do |play|
          ShortcutChoice.new(
            value: play[:card],
            label: _("%{player}: %{card}") % {
              player: participant_name(play[:player]),
              card: card_label(play[:card])
            }
          )
        end
      end
      {
        kind: :browse,
        prompt: _("Cards on the table"),
        choices: choices
      }
    end

    def custom_game_shortcuts(_replay, _viewer)
      []
    end

    # Games with a real card hand may expose local navigation through the
    # currently playable physical cards. The returned hash must contain a
    # stable hand id, every distinct legal action grouped by Card#id, and the
    # subset of cards which are safe to play without any further decision.
    # Returning nil disables the feature for the current phase or variant.
    def playable_card_navigation(_replay, _viewer)
      nil
    end

    # Opt in only when this phase exposes an actual, sortable private hand.
    # Biblios' card/target pickers, boards and dice are deliberately excluded.
    def hand_sorting_available?(_replay, _viewer)
      false
    end

    def hand_sort_shortcuts(replay, viewer)
      return [] unless hand_sorting_available?(replay, viewer)
      [["c", "colour", _("sort cards by suit"), _("Cards sorted by ascending suit."), _("Cards sorted by descending suit.")],
       ["h", "number", _("sort cards by rank"), _("Cards sorted by ascending rank."), _("Cards sorted by descending rank.")],
       ["m", "none", _("restore acquisition order"), _("Cards restored to acquisition order."), nil]].map do |key, mode, label, ascending, descending|
        surface_shortcut(key: key, modifiers: [:shift], label: label, command: "sort_cards",
          payload: { "mode" => mode, "toggle" => mode != "none", "ascending_message" => ascending, "descending_message" => descending })
      end
    end

    def game_shortcuts(replay, viewer)
      shortcuts = GameRoomShortcuts.build(self, shortcut_features, replay, viewer)
      custom = custom_game_shortcuts(replay, viewer).to_a
      if custom.any? { |shortcut| !shortcut.is_a?(GameShortcut) }
        raise ArgumentError, "a custom game shortcut must be a GameShortcut"
      end
      result = shortcuts + custom + playable_card_shortcuts(replay, viewer)
      # Explicit game shortcuts (UNO colour/value/Shift+D, Rummy) retain their
      # labels and behaviour. Add only the missing shared hand commands.
      existing = result.map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
      result += hand_sort_shortcuts(replay, viewer).reject { |shortcut| existing.include?([shortcut.key, shortcut.modifiers.to_a]) }
      keys = result.map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
      raise ArgumentError, "game shortcut keys must be unique" if keys.uniq.length != keys.length

      result
    end

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

    def bot_strategy
      nil
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

    def card_navigation_spec(hand_id:, card_actions:, automatic_card_ids: [])
      {
        hand_id: hand_id.to_s,
        card_actions: card_actions,
        automatic_card_ids: automatic_card_ids.to_a.map(&:to_s)
      }
    end

    def playable_card_shortcuts(replay, viewer)
      specification = playable_card_navigation(replay, viewer)
      return [] if specification == nil
      raise ArgumentError, "playable card navigation must be a hash" if !specification.respond_to?(:key?)

      hand_id = option_source_value(specification, :hand_id).to_s
      raise ArgumentError, "playable card navigation requires a hand id" if hand_id.empty?
      source_actions = option_source_value(specification, :card_actions)
      raise ArgumentError, "playable card navigation requires card actions" if !source_actions.respond_to?(:each_pair)

      card_actions = {}
      source_actions.each_pair do |card_id, actions|
        id = card_id.to_s
        raise ArgumentError, "a playable card requires a physical card id" if id.empty?
        values = actions.to_a
        if values.empty? || values.any? { |action| !action.respond_to?(:key?) }
          raise ArgumentError, "a playable card requires legal action hashes"
        end
        card_actions[id] = values.map { |action| canonical_value(action) }
      end
      automatic_ids = option_source_value(specification, :automatic_card_ids).to_a.map(&:to_s).uniq
      if (automatic_ids - card_actions.keys).any?
        raise ArgumentError, "automatic playable cards must also be navigable"
      end

      auto_action = nil
      auto_card_id = nil
      if card_actions.length == 1
        card_id, actions = card_actions.first
        if automatic_ids.include?(card_id) && actions.length == 1
          auto_card_id = card_id
          auto_action = actions.first
        end
      end
      common_payload = {
        "hand_id" => hand_id,
        "card_ids" => card_actions.keys,
        "auto_card_id" => auto_card_id,
        "auto_action" => auto_action,
        "empty_message" => _("You have no playable card."),
        "focus_surface" => true
      }
      [
        surface_shortcut(
          key: "z",
          label: _("next playable card"),
          command: "navigate_playable_card",
          payload: common_payload.merge("direction" => 1, "shortcut" => "z")
        ),
        surface_shortcut(
          key: "z",
          modifiers: [:shift],
          label: _("previous playable card"),
          command: "navigate_playable_card",
          payload: common_payload.merge("direction" => -1, "shortcut" => "shift+z")
        )
      ]
    end

    def available_content_packs
      return [] if content_pack_kind.to_s.empty?

      content_registry.packs_for(game_id: id, kind: content_pack_kind)
    end

    def available_content_sets(language_id = nil)
      return [] if content_pack_kind.to_s.empty?

      sets = content_registry.pack_sets_for(game_id: id, kind: content_pack_kind)
      return sets if language_id.to_s.empty?

      sets.select { |pack_set| pack_set.language_ids.include?(language_id.to_s) }
    end

    def available_content_languages
      ids = available_content_packs.map(&:language_id).uniq
      ids.map { |language_id| content_registry.language(language_id) }.compact
        .sort_by { |language| [language.label.downcase, language.id] }
    end

    def default_content_language_id(set_id = nil)
      if set_id.to_s.empty?
        return available_content_languages.first&.id
      end

      pack_set = available_content_sets.find { |candidate| candidate.id == set_id.to_s }
      pack_set&.language_ids&.first
    end

    def default_content_set_id(language_id = default_content_language_id)
      sets = available_content_sets(language_id)
      sets = available_content_sets if sets.empty?
      sets.first&.id
    end

    def content_option_definitions(selected = {})
      return [] if content_pack_kind.to_s.empty?

      languages = available_content_languages
      raise ArgumentError, "#{id} requires a #{content_pack_kind} content pack" if available_content_sets.empty?
      language_id = option_source_value(selected, GameRoomContent::LANGUAGE_OPTION_KEY)
      language_id = default_content_language_id if language_id.to_s.empty?
      pack_sets = available_content_sets(language_id)
      pack_sets = available_content_sets if pack_sets.empty?
      [
        OptionDefinition.new(
          key: GameRoomContent::LANGUAGE_OPTION_KEY,
          label: _("Game content language"),
          kind: :choice,
          default: default_content_language_id,
          choices: languages.map do |language|
            OptionChoice.new(value: language.id, label: language.label)
          end
        ),
        OptionDefinition.new(
          key: GameRoomContent::SET_OPTION_KEY,
          label: _("Game content set"),
          kind: :choice,
          default: default_content_set_id(language_id),
          visible_if: single_content_set? ? ->(_options) { false } : nil,
          choices: pack_sets.map do |pack_set|
            OptionChoice.new(value: pack_set.id, label: content_set_choice_label(pack_set, language_id))
          end
        )
      ]
    end

    def content_set_choice_label(pack_set, _language_id = nil)
      pack_set.title
    end

    def normalize_content_options(source, result)
      return if content_pack_kind.to_s.empty?

      requested_language = option_source_value(source, GameRoomContent::LANGUAGE_OPTION_KEY)
      requested_language = default_content_language_id if requested_language.to_s.empty?
      requested_set = option_source_value(source, GameRoomContent::SET_OPTION_KEY)
      requested_set = default_content_set_id(requested_language) if requested_set.to_s.empty?
      known_set = available_content_sets.any? { |candidate| candidate.id == requested_set.to_s }
      known_language = available_content_languages.any? { |candidate| candidate.id == requested_language.to_s }
      if known_set && known_language &&
          !available_content_sets(requested_language).any? { |candidate| candidate.id == requested_set.to_s }
        requested_set = default_content_set_id(requested_language)
      end
      result[GameRoomContent::SET_OPTION_KEY] = requested_set.to_s
      result[GameRoomContent::LANGUAGE_OPTION_KEY] = requested_language.to_s
      pack = content_registry.pack_for(
        game_id: id,
        kind: content_pack_kind,
        set_id: requested_set,
        language_id: requested_language
      )
      stored_pack_id = option_source_value(source, GameRoomContent::PACK_OPTION_KEY)
      stored_version = option_source_value(source, GameRoomContent::PACK_VERSION_KEY)
      stored_checksum = option_source_value(source, GameRoomContent::PACK_CHECKSUM_KEY)
      result[GameRoomContent::PACK_OPTION_KEY] = stored_pack_id == nil ? pack&.id.to_s : stored_pack_id.to_s
      result[GameRoomContent::PACK_VERSION_KEY] = if stored_version == nil
        pack == nil ? 0 : pack.version
      else
        stored_version.to_i
      end
      result[GameRoomContent::PACK_CHECKSUM_KEY] = if stored_checksum == nil
        pack&.checksum.to_s
      else
        stored_checksum.to_s.downcase
      end
    end

    def content_options_error(options)
      return nil if content_pack_kind.to_s.empty?

      values = options.is_a?(Hash) ? options : {}
      set_id = option_source_value(values, GameRoomContent::SET_OPTION_KEY).to_s
      language_id = option_source_value(values, GameRoomContent::LANGUAGE_OPTION_KEY).to_s
      pack_set = content_registry.pack_set(set_id)
      return _("The selected game content set is not installed.") if pack_set == nil
      if !pack_set.supports?(game_id: id, kind: content_pack_kind)
        return _("The selected content set is not compatible with this game.")
      end
      selected = content_registry.pack_for(
        game_id: id,
        kind: content_pack_kind,
        set_id: set_id,
        language_id: language_id
      )
      return _("The selected language is not available for this content set.") if selected == nil
      pack_id = option_source_value(values, GameRoomContent::PACK_OPTION_KEY).to_s
      pack = content_registry.pack(pack_id)
      return _("The selected game content pack is not installed.") if pack == nil
      if !pack.equal?(selected)
        return _("The selected content pack does not match the set and language.")
      end
      if pack.version != option_source_value(values, GameRoomContent::PACK_VERSION_KEY).to_i
        return _("The installed game content pack has a different version.")
      end
      if pack.checksum != option_source_value(values, GameRoomContent::PACK_CHECKSUM_KEY).to_s.downcase
        return _("The installed game content pack does not match the table.")
      end
      nil
    end

    def content_options_summary(options)
      pack = selected_content_pack(options)
      return "" if pack == nil

      language = content_registry.language(pack.language_id)
      pack_set = content_registry.pack_set(pack.set_id)
      _("content: %{title}; language: %{language}") % {
        title: pack_set == nil ? pack.title : content_set_choice_label(pack_set, pack.language_id),
        language: language == nil ? pack.language_id : language.label
      }
    end

    def option_source_value(source, key)
      return source[key] if source.respond_to?(:key?) && source.key?(key)
      symbol = key.to_sym
      return source[symbol] if source.respond_to?(:key?) && source.key?(symbol)

      nil
    end

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

    def bot_identity_value(value, aliases)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), result|
          normalized_key = aliases.fetch(key.to_s.downcase, key)
          result[normalized_key] = bot_identity_value(item, aliases)
        end
      when Array
        value.map { |item| bot_identity_value(item, aliases) }
      when String
        aliases.fetch(value.downcase, value)
      else
        value
      end
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

    def announcement_shortcut(key:, label:, message:)
      GameShortcut.new(
        key: key,
        label: label,
        kind: :announcement,
        message: message
      )
    end

    def browse_shortcut(key:, label:, prompt:, choices:, modifiers: nil)
      GameShortcut.new(
        key: key,
        modifiers: modifiers,
        label: label,
        kind: :browse,
        prompt: prompt,
        choices: choices
      )
    end

    def number_input_shortcut(
      key:,
      label:,
      prompt:,
      action_kind:,
      action_name:,
      value_key:,
      allowed_values:,
      default_value: nil,
      invalid_message: nil
    )
      GameShortcut.new(
        key: key,
        label: label,
        kind: :number_input,
        prompt: prompt,
        action_kind: action_kind,
        action_name: action_name,
        value_key: value_key,
        allowed_values: allowed_values,
        default_value: default_value,
        invalid_message: invalid_message
      )
    end

    def surface_shortcut(key:, label:, command:, payload: {}, modifiers: nil)
      GameShortcut.new(
        key: key,
        modifiers: modifiers,
        label: label,
        kind: :surface,
        action_kind: "surface",
        action_name: command,
        payload: payload
      )
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

    def normalize_option_value(definition, value)
      case definition.kind.to_s
      when "boolean"
        value == true || value.to_s == "1" || value.to_s.downcase == "true"
      when "integer"
        Integer(value.to_s, 10)
      when "choice"
        choices = definition.choices.to_a
        selected = choices.find { |choice| choice.value.to_s == value.to_s }
        selected ||= choices.find { |choice| choice.value.to_s == definition.default.to_s }
        selected == nil ? nil : selected.value
      when "multiple_choice"
        choices = definition.choices.to_a
        valid_mask = (1 << choices.length) - 1
        if value.is_a?(Array)
          requested = value.map(&:to_s)
          choices.each_with_index.reduce(0) do |mask, (choice, index)|
            requested.include?(choice.value.to_s) ? mask | (1 << index) : mask
          end
        else
          value.to_i & valid_mask
        end
      else
        value
      end
    rescue ArgumentError
      definition.default.to_i
    end

    def selection_value(selection, key)
      return selection[key].to_i if selection.respond_to?(:key?) && selection.key?(key)
      symbol = key.to_sym
      return selection[symbol].to_i if selection.respond_to?(:key?) && selection.key?(symbol)

      0
    end
  end
end
