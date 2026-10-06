module GameRoomGames
  using GameRoomLocalization::Translations

  class MilleBornes
    def surface_spec(replay, viewer)
      state = replay.state
      actions = legal_actions(replay, viewer)
      hand = hand_for(state, viewer)
      cards = hand.each_with_index.map do |card, position|
        plays = actions.select { |action| action["card"] == card && action["action"] != "discard" }
        dirty = plays.find { |action| action["action"] == "dirty_trick" }
        plays = [dirty] if dirty
        target_choices = plays.any? { |action| action.key?("target") } && !(state[:players].length == 2 && plays.length == 1)
        repair_choices = plays.any? { |action| action.key?("problem") }
        choices = target_choices ? plays.map do |action|
          unit = state[:seats][action["target"].to_i]
          GameSurfaces::CardChoice.new(id: action["target"], label: GameRoomContent.utf8(unit_status(state, unit)),
            value: surface_value(action))
        end : []
        if repair_choices
          choices = plays.map do |action|
            GameSurfaces::CardChoice.new(id: action["problem"], label: repair_problem_label(action["problem"]),
              value: surface_value(action))
          end
        end
        discard = actions.find { |action| action["card"] == card && action["action"] == "discard" }
        default = plays.first || discard || { "action" => "play", "card" => card }
        confirmation = plays.empty? && discard ? discard_confirmation(card) : nil
        GameSurfaces::Card.new(id: card, label: card_label(card), value: surface_value(default),
          choices: choices, choice_header: GameRoomContent.utf8(repair_choices ? _("Choose a problem to remove") : _("Choose an opponent")),
          sort_keys: card_sort_keys(card, position), confirmation: confirmation)
      end
      hand_spec = GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(
        id: "hand", header: GameRoomContent.utf8(_("Your hand")), cards: cards,
        empty_label: GameRoomContent.utf8(_("Your hand is empty")), hand_order: hand.dup,
        hand_epoch: [replay.session_identity, state[:seed], state[:round], viewer.to_s.downcase].join(":")
      )])
      commands = []
      if actions.any? { |action| action["action"] == "draw" }
        commands << GameSurfaces::Command.new(id: "draw", label: GameRoomContent.utf8(_("Draw a card")), enabled: true)
      end
      return hand_spec if commands.empty?

      GameSurfaces::CompositeSpec.new(parts: [
        GameSurfaces::SurfacePart.new(id: "hand", surface: hand_spec),
        GameSurfaces::SurfacePart.new(id: "actions", surface: GameSurfaces::CommandPanelSpec.new(commands: commands))
      ])
    end

    def hand_sorting_available?(replay, viewer)
      !hand_for(replay.state, viewer).empty?
    end

    def playable_card_navigation(replay, viewer)
      state = replay.state
      return nil unless state[:phase] == :playing && same_user?(state[:current_player], viewer)
      return nil unless dirty_trick_actions(state, viewer).empty?

      actions = legal_actions(replay, viewer).select { |action| action["action"] == "play" }
      grouped = actions.group_by { |action| action["card"] }
      automatic = grouped.select do |_card, candidates|
        candidates.length == 1 && !candidates.first.key?("problem") &&
          (!candidates.first.key?("target") || state[:players].length == 2)
      end.keys
      card_navigation_spec(hand_id: "hand", card_actions: grouped, automatic_card_ids: automatic)
    end

    def shortcut_features
      [:turn, :hand, :scores]
    end

    def shortcut_feature_data(feature, replay, viewer)
      case feature.to_sym
      when :hand
        cards = hand_for(replay.state, viewer)
        text = cards.empty? ? _("Your hand is empty.") : _("Your hand: %{cards}.") % { cards: cards.map { |card| card_label(card) }.join("; ") }
        { message: GameRoomContent.utf8(text) }
      when :scores
        { message: score_text(replay) }
      else
        super
      end
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      own = unit_for(state, viewer)
      shortcuts = []
      if own
        shortcuts << announcement_shortcut(key: "i", label: _("read your mileage, hazards and safeties"),
          message: unit_status(state, own))
      end
      shortcuts << GameShortcut.new(key: "i", modifiers: [:shift], kind: :announcement,
        label: _("read every player's mileage, hazards and safeties"),
        message: GameRoomContent.utf8(state[:tracks].each_index.map { |unit| unit_status(state, unit) }.join("; ")))
      actions = legal_actions(replay, viewer)
      if actions.any? { |action| action["action"] == "draw" }
        shortcuts << GameShortcut.new(key: "space", label: _("draw a card"), kind: :action,
          action_kind: "command", action_name: "draw")
      end
      discards = actions.select { |action| action["action"] == "discard" }
      unless discards.empty?
        shortcuts << surface_shortcut(key: "j", label: _("discard the selected card"), command: "selected_card_action",
          payload: { "hand_id" => "hand", "actions" => discards.to_h { |action| [action["card"], action] },
            "shortcut" => "j" })
        shortcuts << GameShortcut.new(key: "delete", label: _("choose a card to discard"), kind: :choice,
          prompt: GameRoomContent.utf8(_("Choose a card to discard")), action_kind: "card", action_name: "discard",
          value_key: "card", choices: discards.map do |action|
            ShortcutChoice.new(value: action["card"], label: card_label(action["card"]))
          end)
      end
      shortcuts
    end

    def participant_status(replay, participant, connected: true)
      unit = unit_for(replay.state, participant)
      connection = super
      return connection if unit == nil

      [connection, unit_status(replay.state, unit)].compact.join("; ")
    end

    def result_text(replay)
      return nil unless replay.finished?
      return _("The game ended in a draw.") if replay.draw
      unit = replay.state[:teams] ? replay.winner.delete_prefix("team:").to_i : unit_for(replay.state, replay.winner)
      GameRoomContent.utf8(_("%{player} won the game.") % { player: unit_label(replay.state, unit) })
    end

    def describe_event(event, repository, replay, _viewer)
      event_id = repository.event_id(event)
      replay.history.select { |entry| entry.event_id == event_id }.map(&:text)
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      return nil if before_replay == nil || history.empty?
      return nil if before_replay.history.any? { |entry| entry.event_id == history.first.event_id }

      cues = case event["action"]
      when "deal" then "shuffle"
      when "draw" then "draw"
      when "discard" then "play"
      when "play", "dirty_trick"
        selection = selection_from_event(event)
        sound = card_sound(card_type(selection.fetch("card")))
        event["action"] == "dirty_trick" ? [sound, "mille_dirty_trick"] : sound
      end
      if after_replay.state[:recycle_count] > before_replay.state[:recycle_count]
        cues = ["card-shuffle"] + Array(cues)
      end
      cues
    end

    private

    def discard_confirmation(card)
      GameRoomContent.utf8(_("Discard %{card}?")) % { card: card_label(card) }
    end

    def card_sound(type)
      {
        "25" => "mille_distance_25", "50" => "mille_distance_50", "75" => "mille_distance_75",
        "100" => "mille_distance_100", "200" => "mille_distance_200",
        "stop" => "mille_red_light", "speed_limit" => "mille_speed_limit", "go" => "mille_start",
        "out_of_gas" => "mille_fuel_drain", "fuel" => "mille_refuel",
        "flat_tire" => "mille_tire_puncture", "spare_tire" => "mille_wheel_change",
        "accident" => "mille_accident", "repairs" => "mille_repair",
        "end_limit" => "mille_end_speed_limit", "extra_tank" => "mille_extra_tank",
        "puncture_proof" => "mille_puncture_proof", "counterflow" => "mille_counterflow",
        "end_counterflow" => "mille_end_counterflow", "right_of_way" => "mille_right_of_way",
        "driving_ace" => "mille_driving_ace", "instant_repair" => "mille_instant_repair"
      }.fetch(type, "play")
    end

    def current_turn_shortcut_text(replay, viewer)
      return result_text(replay) if replay.finished?
      return _("Waiting for the next deal.") if [:awaiting_deal, :round_complete].include?(replay.state[:phase])
      if replay.state[:phase] == :awaiting_draw
        return GameRoomContent.utf8(_("%{player} must draw a card.") % { player: participant_name(replay.current_player) })
      end
      super
    end

    def card_label(card)
      type = card_type(card)
      text = if DISTANCES.include?(type)
        _("%{distance} miles") % { distance: type.to_i }
      else
        case type
        when "stop" then _("Red light")
        when "speed_limit" then _("Speed limit")
        when "counterflow" then _("Counterflow")
        when "out_of_gas" then _("Out of gas")
        when "flat_tire" then _("Flat tire")
        when "accident" then _("Accident")
        when "go" then _("Green light")
        when "end_limit" then _("End of speed limit")
        when "end_counterflow" then _("End of counterflow")
        when "fuel" then _("Gas")
        when "spare_tire" then _("Spare tire")
        when "repairs" then _("Repairs")
        when "instant_repair" then _("Instant repair")
        when "right_of_way" then _("Right of way")
        when "extra_tank" then _("Extra tank")
        when "puncture_proof" then _("Puncture-proof")
        when "driving_ace" then _("Driving ace")
        else raise ArgumentError, "unknown Mille Bornes card"
        end
      end
      GameRoomContent.utf8(text)
    end

    def card_sort_keys(card, position)
      type = card_type(card)
      group = if DISTANCES.include?(type)
        0
      elsif HAZARDS.include?(type)
        1
      elsif SAFETIES.include?(type)
        3
      else
        2
      end
      rank = DISTANCES.include?(type) ? type.to_i : CARD_ORDER.index(type)
      { "colour" => [group, rank, card], "number" => [rank, group, card], "none" => [position] }
    end

    def surface_value(action)
      [action["action"], action["card"], action["target"] || action["problem"] || action["reaction"]].join("|")
    end

    def repair_problem_label(problem)
      problem == "go" ? GameRoomContent.utf8(_("No green light")) : card_label(problem)
    end

    def unit_label(state, unit)
      players = state[:players].each_with_index.filter_map do |player, seat|
        participant_name(player) if state[:seats][seat] == unit
      end
      return GameRoomContent.utf8(players.first.to_s) unless state[:teams]
      GameRoomContent.utf8(_("Team %{team}: %{players}") % { team: unit + 1, players: players.join(", ") })
    end

    def unit_status(state, unit)
      track = state[:tracks][unit]
      conditions = [track[:moving] ? _("Moving") : _("Stopped")]
      conditions.concat(track[:hazards].map { |type| card_label(type) })
      conditions << card_label("speed_limit") if track[:speed_limit]
      conditions << card_label("counterflow") if track[:counterflow]
      safeties = track[:safeties].empty? ? _("none") : track[:safeties].map { |type| card_label(type) }.join(", ")
      GameRoomContent.utf8(_("%{player}: %{miles} miles; %{status}; safeties: %{safeties}; 200-mile cards: %{count} of 2.") % {
        player: unit_label(state, unit), miles: track[:miles], status: conditions.join(", "),
        safeties: safeties, count: track[:two_hundreds]
      })
    end

    def score_text(replay)
      state = replay.state
      participant_points = participant_scores(replay)
      scores = state[:tracks].each_index.to_h do |unit|
        player = state[:players][state[:seats].index(unit)]
        [unit, participant_points.fetch(player)]
      end
      GameRoomContent.utf8(score_announcement_order(scores.keys, scores).map do |unit|
        _("%{player}: %{score} points") % { player: unit_label(state, unit), score: scores[unit] }
      end.join("; "))
    end
  end
end
