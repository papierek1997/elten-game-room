require "json"
require "securerandom"
require_relative "base"
require_relative "../lib/hidden_submissions"
require_relative "../lib/game_participants"
require_relative "../lib/battleship_strategy"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Battleship < Base
    SIZE = 10
    ROUND_ID = "fleet".freeze
    FLEETS = {
      "polish" => [4, 3, 3, 2, 2, 2, 1, 1, 1, 1].freeze,
      "classic" => [5, 4, 3, 3, 2].freeze
    }.freeze
    FLEET_CHOICES = [
      OptionChoice.new(value: "polish", label: _("One 4, two 3, three 2 and four 1")),
      OptionChoice.new(value: "classic", label: _("5, 4, 3, 3 and 2"))
    ].freeze
    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      kinds = history.map(&:kind)
      cues = []
      cues << "play" if kinds.include?(:seal)
      cues << random_variant.call(%w[rocket_launch1 rocket_launch2 rocket_launch3]) if kinds.include?(:shoot)
      cues << "rocket_miss" if kinds.include?(:miss)
      cues << random_variant.call(%w[hit_ship1 hit_ship2]) if (kinds & [:hit, :sunk]).any?
      cues
    end

    def id
      "battleship"
    end

    def controller_change_phase_error(_replay)
      _("The current game contains private data that cannot be transferred at this stage.")
    end

    def name
      _("Battleship")
    end

    def short_description
      _("Place your fleet, work out where your opponent's ships are and sink them before you lose your own.")
    end

    def rule_sections
      generated_rule_sections
    end

    def minimum_players
      2
    end

    def maximum_players
      2
    end

    def supports_bots?
      true
    end

    def perfect_information?
      false
    end

    def supports_saved_games?
      false
    end

    def serial_event_presentation?
      true
    end

    def prepare_view(replay, viewer, context: nil)
      remember_fleet(replay.state, viewer, context)
    end

    def bot_strategy
      @bot_strategy ||= BattleshipPlanning::Strategy.new
    end

    def option_definitions
      [
        OptionDefinition.new(key: "fleet", label: _("Fleet"), kind: :choice, default: "polish", choices: FLEET_CHOICES),
        OptionDefinition.new(key: "touching", label: _("Ships may touch"), kind: :boolean, default: false)
      ]
    end

    def options_summary(options)
      values = normalize_options(options)
      fleet = FLEET_CHOICES.find { |choice| choice.value == values["fleet"] }
      return fleet.label.to_s if !values["touching"]

      _("%{fleet}; ships may touch") % { fleet: fleet&.label }
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session["options"]))
      accepted = []
      history = [starting_history(players)]

      events.each do |event|
        break if state[:phase] == :finished

        actor = repository.actor_of(event, session)
        applied = case event["action"].to_s
        when "start" then same_user?(actor, players.first) && apply_begin(state, event, repository, history)
        when "place" then apply_place(state, event, actor, repository, history)
        when "shoot" then apply_shoot(state, event, actor, repository, history)
        when "answer" then apply_answer(state, event, actor, repository, history)
        when "open" then apply_open(state, event, actor)
        when "fleet" then apply_fleet(state, event, actor, repository, history)
        else false
        end
        accepted << event if applied
      end

      Replay.new(
        board: nil, players: players, current_player: state[:current_player],
        winner: state[:winner], draw: state[:tie], accepted_events: accepted,
        history: history, state: state
      )
    end

    def automatic_action(replay, actor, context: nil)
      state = replay.state
      remember_fleet(state, actor, context)
      return nil if replay.finished?
      return { "kind" => "command", "action" => "begin" } if !state[:started] && same_user?(actor, state[:players].first)

      case state[:phase]
      when :answering
        same_user?(answerer(state), actor) ? { "kind" => "command", "action" => "answer" } : nil
      when :revealing
        sealed?(state, actor) && !opened?(state, actor) ? { "kind" => "command", "action" => "open" } : nil
      else
        nil
      end
    end

    def automatic_action_allowed?(replay, actor, table_owner:)
      return true if same_user?(actor, table_owner)

      [:answering, :revealing].include?(replay.state[:phase])
    end

    def automatic_action_due?(replay, actor, context: nil)
      automatic_action(replay, actor, context: context) != nil
    end

    def active_actors(replay)
      state = replay.state
      return state[:players].reject { |player| sealed?(state, player) } if state[:phase] == :placing
      return state[:players].reject { |player| opened?(state, player) } if state[:phase] == :revealing
      return [answerer(state)].compact if state[:phase] == :answering

      replay.current_player == nil ? [] : [replay.current_player]
    end

    def automatic_actor(replay, viewer, table_owner:)
      return viewer if [:answering, :revealing].include?(replay.state[:phase])
      super
    end

    def required_decision_key(replay, viewer)
      return nil if replay == nil || replay.finished?
      if replay.state[:phase] == :placing
        return [:placing] if active_actors(replay).any? { |actor| same_user?(actor, viewer) }
        return nil
      end
      return nil unless replay.state[:phase] == :playing
      super
    end

    def concurrent_session_input?(before, after, selection)
      before.state[:phase] == :placing && after.state[:phase] == :placing &&
        %w[select seal random_fleet].include?(selection['action'].to_s)
    end

    def answerer(state)
      state[:pending] == nil ? nil : opponent(state, state[:pending]["shooter"])
    end

    def turn_announcement(replay, viewer)
      return nil if player_key(replay.state, viewer) == nil
      return super if replay.state[:phase] != :placing
      return nil if sealed?(replay.state, viewer)

      _("Place your fleet.")
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if state == nil || state[:phase] == :finished || player_key(state, actor) == nil

      case state[:phase]
      when :placing
        return [] if sealed?(state, actor)
        GameRoomParticipants.bot?(actor) ? [{ "kind" => "command", "action" => "seal" }] : []
      when :playing
        return [] if !same_user?(state[:current_player], actor)

        open_cells(state, actor).map { |cell| { "kind" => "grid", "action" => "select", "x" => cell % SIZE, "y" => cell / SIZE } }
      when :answering
        same_user?(answerer(state), actor) ? [{ "kind" => "command", "action" => "answer" }] : []
      when :revealing
        sealed?(state, actor) && !opened?(state, actor) ? [{ "kind" => "command", "action" => "open" }] : []
      else
        []
      end
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?
      return [:invalid, nil] if player_key(state, actor) == nil

      case selection["action"].to_s
      when "begin"
        state[:started] || !same_user?(actor, state[:players].first) ? [:invalid, nil] : [:ok, event_plan("start", "")]
      when "select"
        state[:phase] == :placing ? seal_fleet(selection, state, actor, context) : shoot(selection, state, actor)
      when "seal"
        seal_fleet(selection, state, actor, context)
      when "random_fleet"
        seal_fleet(selection, state, actor, context, random: true)
      when "answer"
        answer_shot(state, actor, context)
      when "open"
        open_fleet(state, actor, context)
      else
        [:invalid, nil]
      end
    end

    def surface_spec(replay, viewer)
      state = replay.state
      return spectator_surface(state) if player_key(state, viewer) == nil
      if state[:phase] == :placing
        return sealed?(state, viewer) ? waiting(_("Waiting for the other fleet")) : fleet_grid(state, viewer)
      end

      GameSurfaces::CompositeSpec.new(parts: [
        GameSurfaces::SurfacePart.new(
          id: "enemy", surface: grid(target_cells(state, viewer), enemy_header(replay, viewer))
        ),
        GameSurfaces::SurfacePart.new(
          id: "own", surface: grid(board_cells(state, viewer), own_header(state, viewer))
        )
      ])
    end

    def enemy_header(replay, viewer)
      state = replay.state
      return _("Enemy waters. %{result}") % { result: result_text(replay) } if replay.finished?
      return _("Enemy waters. Choose a square and press Enter.") if same_user?(state[:current_player], viewer) && state[:phase] == :playing

      _("Enemy waters. %{turn}") % { turn: current_turn_shortcut_text(replay, viewer) }
    end

    def own_header(state, viewer)
      struck = hits_on(state, player_key(state, viewer))
      _("Your waters. %{left} of %{total} squares afloat.") % {
        left: fleet_of(state).sum - struck, total: fleet_of(state).sum
      }
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      if player_key(state, viewer) == nil
        return [announcement_shortcut(key: "l", label: _("read the last shot"), message: last_shot_text(state))]
      end
      shortcuts = [
        announcement_shortcut(key: "f", label: _("read your fleet"), message: own_fleet_text(state, viewer)),
        GameShortcut.new(key: "f", modifiers: [:shift], label: _("read the enemy fleet"),
          kind: :announcement, message: enemy_fleet_text(state, viewer)),
        announcement_shortcut(key: "l", label: _("read the last shot"), message: last_shot_text(state)),
        announcement_shortcut(key: "m", label: _("read your hits and misses"), message: tally_text(state, viewer)),
        browse_shortcut(key: "l", modifiers: [:control], label: _("browse your shots"),
          prompt: _("Your shots"), choices: shot_choices(state, viewer))
      ]
      if state[:phase] == :placing && !sealed?(state, viewer)
        shortcuts << surface_shortcut(key: "backspace", label: _("clear the marked bow or take back the last ship"), command: "undo")
      end
      shortcuts
    end

    def move_error(status)
      case status
      when :not_a_line then _("A ship must lie in one row or one column.")
      when :no_such_ship then _("You have no ship of that length left.")
      when :ship_does_not_fit then _("The ship does not fit there.")
      when :already_shot then _("You have already shot at that square.")
      when :not_ready then _("Place every ship before sealing the fleet.")
      when :local_storage_unavailable then _("Your fleet could not be sealed on this computer. Try again.")
      when :own_board then _("Choose a square on the enemy board to shoot.")
      else super
      end
    end

    def describe_event(event, repository, replay, viewer)
      event_id = repository.event_id(event)
      entries = replay.history.select { |entry| entry.event_id.to_i == event_id.to_i }
      entries.empty? ? nil : entries.map(&:text)
    end

    def describe_event_for_display(event, repository, replay, viewer, surface_state: {})
      if event["action"].to_s == "place" && surface_state["setup_mode"] == "random"
        entry = replay.history.find do |item|
          item.kind == :seal && item.event_id.to_i == repository.event_id(event).to_i && same_user?(item.actor, viewer)
        end
        return [_("Your ships have been placed automatically.")] if entry != nil
      end

      super
    end

    def bot_observation(replay, actor)
      state = replay.state
      {
        "phase" => state[:phase].to_s,
        "current_player" => state[:current_player],
        "shots" => state[:shots].fetch(player_key(state, actor), {}),
        "fleet" => fleet_of(state),
        "viewer" => actor.to_s
      }
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      return 0.0 if action["action"].to_s != "select" || state[:phase] != :playing

      bot_strategy.cell_value(self, state, player_key(state, actor), action["y"].to_i * SIZE + action["x"].to_i)
    end

    def fleet_of(state)
      state[:fleet]
    end

    def board_size
      SIZE
    end

    def legal_fleet?(state, ships)
      return false unless fleet_shape?(ships)
      sizes = ships.map(&:length).sort
      return false if sizes != fleet_of(state).sort
      return false if ships.any? { |cells| !straight?(cells) }

      taken = ships.flatten
      return false if taken.uniq.length != taken.length
      return false if taken.any? { |cell| !cell.between?(0, SIZE * SIZE - 1) }
      return true if state[:options]["touching"]

      ships.each_with_index.none? do |cells, index|
        others = ships.each_with_index.reject { |_, other| other == index }.flat_map(&:first)
        cells.any? { |cell| neighbours(cell).any? { |near| others.include?(near) } }
      end
    end

    private

    def fleet_shape?(ships)
      ships.is_a?(Array) && ships.length.between?(1, 10) && ships.all? do |cells|
        cells.is_a?(Array) && cells.length.between?(1, 5) && cells.all? do |cell|
          cell.is_a?(Integer) && cell.between?(0, SIZE * SIZE - 1)
        end
      end
    end

    # Two base-36 digits per square plus one separator per ship: the largest
    # supported fleet is 51 ASCII characters, within the transport's 64 limit.
    # Keep the original order: the commitment hashes that exact payload.
    def encode_fleet(ships)
      "1:" + ships.map { |cells| cells.map { |cell| cell.to_s(36).rjust(2, "0") }.join }.join(".")
    end

    def decode_fleet(value)
      text = value.to_s
      if text.start_with?("1:")
        return nil if text.length > 64
        parts = text[2..-1].split(".", -1)
        return nil unless parts.all? { |part| /\A(?:[0-2][0-9a-z]){1,5}\z/.match?(part) }
        parts.map { |part| part.scan(/../).map { |cell| cell.to_i(36) } }
      else
        JSON.parse(text)
      end
    rescue JSON::ParserError
      nil
    end

    def spectator_surface(state)
      GameSurfaces::CompositeSpec.new(parts: state[:players].map do |player|
        shots = state[:shots].fetch(opponent(state, player), {})
        revealed = state[:phase] == :finished ? state[:fleets].fetch(player, []).flatten : []
        cells = (0...(SIZE * SIZE)).map do |cell|
          marks = []
          marks << _("ship") if revealed.include?(cell)
          marks << result_label(shots[cell]) if shots.key?(cell)
          marks.join(", ")
        end
        GameSurfaces::SurfacePart.new(id: "spectator_#{player}",
          surface: grid(cells, _("%{player}'s waters") % { player: participant_name(player) }))
      end)
    end

    def initial_state(players, options)
      {
        players: players,
        options: options,
        fleet: FLEETS.fetch(options["fleet"], FLEETS["polish"]),
        commitments: {},
        started: false,
        shots: players.each_with_object({}) { |player, result| result[player] = {} },
        order: [],
        pending: nil,
        fleets: {},
        nonces: {},
        invalid: [],
        phase: :placing,
        current_player: players.first,
        winner: nil,
        tie: false
      }
    end

    def turn_phase_kind(replay)
      replay&.state&.dig(:phase) == :placing ? :placement : super
    end

    def apply_place(state, event, actor, repository, history)
      return false if state[:phase] != :placing || sealed?(state, actor)

      digest = event["value"].to_s
      return false if !/\A[0-9a-f]{64}\z/.match?(digest)

      player = player_key(state, actor)
      return false if player == nil

      state[:commitments][player] = digest
      event_id = repository.event_id(event)
      history << entry("seal:#{event_id}", _("%{player} sealed the fleet.") % { player: participant_name(player) },
        event_id, player, :seal)
      if state[:players].all? { |candidate| sealed?(state, candidate) }
        state[:phase] = :playing
        state[:current_player] = state[:players].first
      end
      true
    end

    def apply_shoot(state, event, actor, repository, history)
      return false if state[:phase] != :playing || !same_user?(state[:current_player], actor)

      cell = Integer(event["value"].to_s, 10)
      return false if !cell.between?(0, SIZE * SIZE - 1)

      player = player_key(state, actor)
      return false if state[:shots][player].key?(cell)

      state[:pending] = { "shooter" => player, "cell" => cell }
      state[:phase] = :answering
      event_id = repository.event_id(event)
      history << entry("shoot:#{event_id}", _("%{player} shoots at %{field}.") % {
        player: participant_name(player), field: field_of(cell)
      }, event_id, player, :shoot)
      true
    rescue ArgumentError
      false
    end

    def apply_answer(state, event, actor, repository, history)
      return false if state[:phase] != :answering || !same_user?(answerer(state), actor)

      result = event["value"].to_s
      return false if !%w[hit miss sunk].include?(result)

      target = answerer(state)
      shooter = state[:pending]["shooter"]
      cell = state[:pending]["cell"]
      state[:shots][shooter][cell] = result
      state[:order] << [shooter, cell, result]
      state[:pending] = nil
      event_id = repository.event_id(event)
      history << entry("answer:#{event_id}", answer_text(cell, result), event_id, shooter, result.to_sym)
      afloat = fleet_of(state).sum - hits_on(state, target)
      if afloat <= 0 || open_cells(state, shooter).length < afloat
        state[:phase] = :revealing
        state[:current_player] = nil
      else
        state[:phase] = :playing
        state[:current_player] = shooter == state[:players].first ? state[:players].last : state[:players].first
      end
      true
    end

    def apply_open(state, event, actor)
      return false if state[:phase] != :revealing
      player = player_key(state, actor)
      return false if player == nil || state[:nonces].key?(player)

      nonce = event["value"].to_s
      return false if !/\A[0-9a-f]{64}\z/.match?(nonce)

      state[:nonces][player] = nonce
      true
    end

    def apply_fleet(state, event, actor, repository, history)
      return false if state[:phase] != :revealing

      player = player_key(state, actor)
      return false if player == nil || state[:fleets].key?(player) || !state[:nonces].key?(player)

      ships = decode_fleet(event["value"])
      return false unless legal_fleet?(state, ships)

      state[:fleets][player] = ships
      event_id = repository.event_id(event)
      history << entry("open:#{event_id}", _("%{player} opened the fleet.") % { player: participant_name(player) },
        event_id, player, :open)
      conclude(state, event_id, history) if state[:players].all? { |candidate| state[:fleets].key?(candidate) }
      true
    end

    def conclude(state, event_id, history)
      state[:players].each do |player|
        state[:invalid] << player if !honest?(state, player)
      end
      state[:phase] = :finished
      state[:current_player] = nil
      honest = state[:players].reject { |player| state[:invalid].include?(player) }
      if honest.length == 1
        state[:winner] = honest.first
        history << entry("cheat:#{event_id}", _("%{player} did not keep to the sealed fleet.") % {
          player: participant_name(state[:invalid].first)
        }, event_id, state[:invalid].first, :invalid)
      elsif honest.empty?
        state[:tie] = true
      else
        loser = state[:players].find { |player| hits_on(state, player) >= fleet_of(state).sum }
        state[:winner] = loser == nil ? nil : opponent(state, loser)
        state[:tie] = state[:winner] == nil
      end
      history << entry("verified:#{event_id}", _("Both fleets match their seals.") % {}, event_id, "", :verified) if state[:invalid].empty?
      history << result_history(event_id: event_id, winner: state[:winner], draw: state[:tie])
    end

    def honest?(state, player)
      ships = state[:fleets][player]
      nonce = state[:nonces][player]
      commitment = state[:commitments][player]
      return false if ships == nil || nonce == nil || commitment == nil
      return false if !HiddenSubmissions::Commitment.valid?(payload: { "ships" => ships }, nonce: nonce, commitment: commitment)
      return false if !legal_fleet?(state, ships)

      struck = []
      state[:order].each do |shooter, cell, result|
        next if same_user?(shooter, player)

        ship = ships.find { |cells| cells.include?(cell) }
        if ship == nil
          return false if result != "miss"

          next
        end
        struck << cell
        return false if result != (ship.all? { |square| struck.include?(square) } ? "sunk" : "hit")
      end
      true
    end

    def apply_begin(state, event, repository, history)
      return false if state[:started]

      state[:started] = true
      history << entry("start", _("The fleets are being placed."), repository.event_id(event), "", :phase)
      true
    end

    def seal_fleet(selection, state, actor, context, random: false)
      return [:invalid, nil] if state[:phase] != :placing || sealed?(state, actor)
      return [:invalid, nil] if context == nil || context.hidden_submissions == nil

      ships = random ? [] : parse_ships(selection["ships"])
      if ships.empty?
        return [:not_ready, nil] if !random && !GameRoomParticipants.bot?(actor)

        previous = context.hidden_submissions.reveal(session_id: context.session_id, round_id: ROUND_ID, user: actor)
        stored = previous&.payload.to_h.fetch("ships", [])
        ships = previous != nil && context.hidden_submissions.verify(previous) && legal_fleet?(state, stored) ? stored : random_fleet(state)
      end
      return [:not_ready, nil] if ships.length != fleet_of(state).length
      return [:invalid, nil] if !legal_fleet?(state, ships)

      envelope = context.hidden_submissions.prepare(
        session_id: context.session_id, round_id: ROUND_ID, user: actor, payload: { "ships" => ships }
      )
      @sealed = { [actor.to_s.downcase, envelope.commitment] => ships }
      [:ok, event_plan("place", envelope.commitment)]
    rescue HiddenSubmissions::StorageError
      [:local_storage_unavailable, nil]
    end

    def parse_ships(value)
      return [] if value.to_s.empty?

      ships = JSON.parse(value.to_s)
      fleet_shape?(ships) ? ships : []
    rescue JSON::ParserError
      []
    end

    def fleet_grid(state, viewer)
      GameSurfaces::FleetGridSpec.new(
        width: SIZE, height: SIZE, header: _("Mark the bow and then the stern of each ship."),
        cells: rows_of(board_cells(state, viewer)), row_origin: :top,
        epoch: "#{viewer}:#{fleet_of(state).length}",
        setup_header: _("How would you like to arrange your fleet?"),
        random_label: _("Randomly"), manual_label: _("Manually"),
        place: ->(ships, bow, stern) { place_result(state, ships, bow, stern) },
        complete: ->(ships) { ships.length == fleet_of(state).length },
        status: ->(ships) { placement_status(state, ships) },
        bow_check: ->(ships, cell) { bow_refusal(state, ships, cell) },
        confirm_message: _("The fleet is ready. Do you want to seal it?"),
        placed_message: ->(cells, _ships) { placed_text(cells) },
        action_name: "seal", ship_label: _("ship"), bow_label: _("bow"),
        bow_message: _("Bow marked. Choose the stern, or the same square for one mast."),
        cancel_message: _("Bow cleared."),
        removed_message: _("The last ship was taken back."),
        empty_message: _("No ship has been placed yet.")
      )
    end

    def place_result(state, ships, bow, stern)
      placed = ships.to_a.map { |cells| cells.to_a.map(&:to_i) }
      cells = segment(bow, stern)
      return [nil, _("A ship must lie in one row or one column.")] if cells == nil
      return [nil, _("You have no ship of that length left.")] if !remaining_sizes(state, placed).include?(cells.length)
      return [nil, _("The ship does not fit there.")] if !fits?(state, placed, cells)

      [cells, nil]
    end

    def placed_text(cells)
      _("%{size} masts from %{bow} to %{stern} placed.") % {
        size: cells.length, bow: field_of(cells.first), stern: field_of(cells.last)
      }
    end

    def bow_refusal(state, ships, cell)
      placed = ships.to_a.map { |cells| cells.to_a.map(&:to_i) }
      sizes = remaining_sizes(state, placed).uniq
      return nil if sizes.any? { |size| room_from?(state, placed, cell, size) }

      _("No ship you still own fits from %{field}.") % { field: field_of(cell) }
    end

    def room_from?(state, placed, cell, size)
      [true, false].any? do |horizontal|
        [1, -1].any? do |direction|
          cells = span_from(cell, size, horizontal, direction)
          cells != nil && fits?(state, placed, cells)
        end
      end
    end

    def span_from(origin, size, horizontal, direction)
      cells = (0...size).map do |step|
        horizontal ? origin + step * direction : origin + step * direction * SIZE
      end
      return nil if cells.any? { |cell| !cell.between?(0, SIZE * SIZE - 1) }
      return nil if horizontal && cells.any? { |cell| cell / SIZE != origin / SIZE }

      cells
    end

    def placement_status(state, ships)
      left = remaining_sizes(state, ships.to_a)
      return _("The fleet is ready.") if left.empty?

      _("Ships left: %{sizes}") % { sizes: left.sort.reverse.join(", ") }
    end

    def remember_fleet(state, actor, context)
      @sealed ||= {}
      key = [actor.to_s.downcase, state[:commitments][player_key(state, actor)]]
      return if @sealed.key?(key) || !sealed?(state, actor)
      return if context == nil || context.hidden_submissions == nil

      envelope = context.hidden_submissions.reveal(
        session_id: context.session_id, round_id: ROUND_ID, user: actor,
        commitment: state[:commitments][player_key(state, actor)]
      )
      return if envelope == nil
      ships = envelope.payload["ships"]
      return unless legal_fleet?(state, ships)
      @sealed = { key => ships }
    rescue HiddenSubmissions::StorageError
      nil
    end

    def board_cells(state, viewer, ships = nil)
      player = player_key(state, viewer)
      enemy = state[:shots].fetch(opponent(state, player), {})
      cache_key = [viewer.to_s.downcase, state[:commitments][player]]
      occupied = (ships || state[:fleets][player] || (@sealed || {})[cache_key]).to_a.flatten
      (0...(SIZE * SIZE)).map do |cell|
        marks = []
        marks << _("ship") if occupied.include?(cell)
        marks << result_label(enemy[cell]) if enemy.key?(cell)
        marks.join(", ")
      end
    end

    def segment(first, second)
      return [first] if first == second

      low, high = [first, second].minmax
      if first / SIZE == second / SIZE
        (low..high).to_a
      elsif first % SIZE == second % SIZE
        (low..high).step(SIZE).to_a
      end
    end

    def remaining_sizes(state, draft)
      sizes = fleet_of(state).dup
      draft.each do |cells|
        index = sizes.index(cells.length)
        sizes.delete_at(index) if index != nil
      end
      sizes
    end

    def answer_shot(state, actor, context)
      return [:invalid, nil] if state[:phase] != :answering || !same_user?(answerer(state), actor)

      ships = sealed_fleet(state, actor, context)
      return [:invalid, nil] if ships == nil

      cell = state[:pending]["cell"].to_i
      [:ok, event_plan("answer", shot_result(state, ships, cell))]
    end

    def shot_result(state, ships, cell)
      ship = ships.find { |cells| cells.to_a.map(&:to_i).include?(cell) }
      return "miss" if ship == nil

      struck = state[:shots].fetch(state[:pending]["shooter"], {})
      ship.to_a.map(&:to_i).all? { |square| square == cell || struck[square] != "miss" && struck.key?(square) } ? "sunk" : "hit"
    end

    def answer_text(cell, result)
      case result
      when "miss" then _("%{field}: miss.") % { field: field_of(cell) }
      when "sunk" then _("%{field}: hit and sunk.") % { field: field_of(cell) }
      else _("%{field}: hit.") % { field: field_of(cell) }
      end
    end

    def open_fleet(state, actor, context)
      return [:invalid, nil] if state[:phase] != :revealing
      return [:invalid, nil] if context == nil || context.hidden_submissions == nil

      envelope = context.hidden_submissions.reveal(
        session_id: context.session_id, round_id: ROUND_ID, user: actor,
        commitment: state[:commitments][player_key(state, actor)]
      )
      return [:invalid, nil] if envelope == nil || !context.hidden_submissions.verify(envelope)

      [:ok, ActionPlan.new(events: [
        EventCommand.new(action: "open", value: envelope.nonce),
        EventCommand.new(action: "fleet", value: encode_fleet(envelope.payload.fetch("ships", [])))
      ])]
    end

    def shoot(selection, state, actor)
      return [:own_board, nil] if selection["source"].to_s == "own"
      return [:not_your_turn, nil] if state[:phase] != :playing || !same_user?(state[:current_player], actor)

      x, y = selection["x"], selection["y"]
      return [:invalid, nil] unless [x, y].all? { |value| value.is_a?(Integer) && value.between?(0, SIZE - 1) }
      cell = y * SIZE + x
      return [:already_shot, nil] if state[:shots][player_key(state, actor)].key?(cell)

      [:ok, event_plan("shoot", cell.to_s)]
    end

    def sealed_fleet(state, actor, context)
      return nil if context == nil || context.hidden_submissions == nil

      envelope = context.hidden_submissions.reveal(
        session_id: context.session_id, round_id: ROUND_ID, user: actor,
        commitment: state[:commitments][player_key(state, actor)]
      )
      envelope == nil ? nil : envelope.payload.fetch("ships", nil)
    end


    def random_fleet(state)
      fleet_of(state).each_with_object([]) do |size, ships|
        cells = nil
        2_000.times do
          origin = SecureRandom.random_number(SIZE * SIZE)
          candidate = ship_cells(origin, size, SecureRandom.random_number(2).zero?)
          next if candidate == nil || !fits?(state, ships, candidate)

          cells = candidate
          break
        end
        return random_fleet(state) if cells == nil

        ships << cells
      end
    end

    def ship_cells(origin, size, horizontal)
      x = origin % SIZE
      y = origin / SIZE
      return nil if horizontal && x + size > SIZE
      return nil if !horizontal && y + size > SIZE

      (0...size).map { |step| horizontal ? origin + step : origin + step * SIZE }
    end


    def fits?(state, ships, cells)
      taken = ships.flatten
      return false if cells.any? { |cell| taken.include?(cell) }
      return true if state[:options]["touching"]

      cells.none? { |cell| neighbours(cell).any? { |near| taken.include?(near) } }
    end

    def neighbours(cell)
      x = cell % SIZE
      y = cell / SIZE
      result = []
      (-1..1).each do |dx|
        (-1..1).each do |dy|
          nx = x + dx
          ny = y + dy
          next if dx.zero? && dy.zero?
          next if !nx.between?(0, SIZE - 1) || !ny.between?(0, SIZE - 1)

          result << ny * SIZE + nx
        end
      end
      result
    end

    def straight?(cells)
      return true if cells.length == 1

      sorted = cells.sort
      rows = sorted.map { |cell| cell / SIZE }.uniq
      columns = sorted.map { |cell| cell % SIZE }.uniq
      if rows.length == 1
        sorted.each_cons(2).all? { |first, second| second == first + 1 }
      elsif columns.length == 1
        sorted.each_cons(2).all? { |first, second| second == first + SIZE }
      else
        false
      end
    end

    def sealed?(state, actor)
      state[:commitments].key?(player_key(state, actor))
    end

    def opened?(state, actor)
      state[:fleets].key?(player_key(state, actor))
    end

    def hits_on(state, player)
      return 0 if player == nil

      state[:shots].fetch(opponent(state, player), {}).count { |_cell, result| result != "miss" }
    end

    def opponent(state, player)
      state[:players].find { |candidate| !same_user?(candidate, player) }
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def open_cells(state, actor)
      taken = state[:shots].fetch(player_key(state, actor), {})
      (0...(SIZE * SIZE)).reject { |cell| taken.key?(cell) }
    end

    def field_of(cell)
      field_label(cell % SIZE, cell / SIZE)
    end

    def entry(key, text, event_id, actor, kind)
      HistoryEntry.new(key: key, text: text, event_id: event_id, actor: actor, kind: kind)
    end

    def grid(cells, header)
      GameSurfaces::GridSpec.new(width: SIZE, height: SIZE, header: header, cells: rows_of(cells), row_origin: :top)
    end

    def rows_of(cells)
      (0...SIZE).map { |y| (0...SIZE).map { |x| cells[y * SIZE + x].to_s } }
    end

    def waiting(label)
      text = label.to_s.empty? ? _("Waiting for the other player") : label.to_s
      GameSurfaces::CardTableSpec.new(
        zones: [GameSurfaces::CardZoneSpec.new(id: "actions", header: text, cards: [], empty_label: text)]
      )
    end


    def target_cells(state, viewer)
      taken = state[:shots].fetch(player_key(state, viewer), {})
      (0...(SIZE * SIZE)).map { |cell| taken.key?(cell) ? result_label(taken[cell]) : "" }
    end

    def result_label(result)
      case result
      when "miss" then _("miss")
      when "sunk" then _("sunk")
      else _("hit")
      end
    end

    def own_fleet_text(state, viewer)
      total = fleet_of(state).sum
      struck = hits_on(state, player_key(state, viewer))
      _("Your fleet: %{left} of %{total} squares afloat.") % { left: total - struck, total: total }
    end

    def enemy_fleet_text(state, viewer)
      total = fleet_of(state).sum
      struck = state[:shots].fetch(player_key(state, viewer), {}).count { |_cell, result| result != "miss" }
      _("Enemy fleet: %{left} of %{total} squares left.") % { left: total - struck, total: total }
    end

    def last_shot_text(state)
      last = state[:order].last
      return _("No shots have been fired.") if last == nil

      _("%{player}: %{result}") % {
        player: participant_name(last[0]), result: answer_text(last[1], last[2])
      }
    end

    def tally_text(state, viewer)
      shots = state[:shots].fetch(player_key(state, viewer), {})
      _("You fired %{shots} shots, %{hits} of them hits, and sank %{sunk} ships.") % {
        shots: shots.length, hits: shots.count { |_cell, result| result != "miss" },
        sunk: shots.count { |_cell, result| result == "sunk" }
      }
    end

    def shot_choices(state, viewer)
      shots = state[:shots].fetch(player_key(state, viewer), {})
      return [ShortcutChoice.new(value: nil, label: _("You have not fired yet"))] if shots.empty?

      shots.keys.sort.map do |cell|
        ShortcutChoice.new(value: cell, label: answer_text(cell, shots[cell]))
      end
    end
  end
end

require_relative 'generated/rulebooks/battleship'
