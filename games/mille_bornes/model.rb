module GameRoomGames
  using GameRoomLocalization::Translations

  class MilleBornes
    class SessionReplay < Replay
      attr_accessor :session_identity
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session["options"]))
      accepted = []
      history = [starting_history(players)]
      seen = {}
      events.each do |event|
        break if state[:winner] || state[:draw]
        event_id = repository.event_id(event)
        next if seen[event_id]
        actor = repository.actor_of(event, session)
        next unless apply_event(state, event, actor, event_id, history)

        seen[event_id] = true
        accepted << event
      end
      result = SessionReplay.new(players: players, current_player: state[:current_player], winner: state[:winner],
        draw: state[:draw], accepted_events: accepted, history: history, state: state)
      result.session_identity = session["__id"] || session["id"]
      result
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || !same_user?(actor, replay.players.first)
      return nil unless [:awaiting_deal, :round_complete].include?(replay.state[:phase])

      { "kind" => "command", "action" => "deal" }
    end

    def active_actors(replay)
      return [] if replay.finished?
      state = replay.state
      responders = state[:players].select { |player| !dirty_trick_actions(state, player).empty? }
      (responders + [state[:current_player]]).compact.uniq
    end

    def legal_actions(replay, actor, context: nil)
      actions_for_state(replay.state, actor)
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      state = replay.state
      if selection["kind"] == "command" && selection["action"] == "deal"
        return [:not_your_turn, nil] unless same_user?(actor, replay.players.first)
        return [:invalid, nil] unless [:awaiting_deal, :round_complete].include?(state[:phase])
        return [:invalid, nil] if options_error(state[:options], player_count: state[:players].length) || !context&.random_source
        seed = context.random_source.roll(count: 16, sides: 256).values.map do |value|
          (value.to_i - 1).to_s(16).rjust(2, "0")
        end.join
        return [:ok, event_plan("deal", "#{state[:round] + 1}|#{seed}")]
      end
      requested = normalize_selection(selection)
      candidate = actions_for_state(state, actor).find { |action| action == requested }
      return [:invalid, nil] unless candidate

      [:ok, event_plan(candidate["action"], action_value(candidate))]
    end

    def concurrent_session_input?(before, after, selection)
      requested = normalize_selection(selection)
      return false unless requested && requested["action"] == "dirty_trick"
      previous = before.state
      current = after.state
      return false unless before.respond_to?(:session_identity) && after.respond_to?(:session_identity) &&
        before.session_identity != nil && before.session_identity == after.session_identity &&
        previous[:round] == current[:round] && previous[:seed] == current[:seed] &&
        previous[:players] == current[:players]
      reaction = current[:reaction]
      reaction && previous[:reaction] && reaction[:token] == previous[:reaction][:token] &&
        reaction[:token] == requested["reaction"] && [:awaiting_draw, :playing].include?(current[:phase])
    end

    def participant_scores(replay)
      state = replay.state
      state[:players].each_with_index.to_h do |player, seat|
        unit = state[:seats][seat]
        points = state[:scores][unit]
        points += round_points(state[:tracks][unit]) unless [:round_complete, :finished].include?(state[:phase])
        [player, points]
      end
    end

    private

    def initial_state(players, options)
      assignment = team_assignment(options, players: players)
      seats = assignment ? assignment.seats.dup : players.each_index.to_a
      units = assignment ? assignment.team_count : players.length
      {
        players: players.dup, options: options, seats: seats, teams: assignment != nil,
        scores: Array.new(units, 0), tracks: Array.new(units) { fresh_track },
        hands: players.to_h { |player| [player, []] }, draw_pile: [], discard: [], spent: [],
        phase: :awaiting_deal, current_player: nil, round: 0, seed: nil, recycle_count: 0,
        action_number: 0, reaction: nil, winner: nil, draw: false, round_winner: nil,
        round_scores: []
      }
    end

    def fresh_track
      { miles: 0, two_hundreds: 0, moving: false, hazards: [], speed_limit: false,
        safeties: [], dirty_tricks: 0 }
    end

    def apply_event(state, event, actor, event_id, history)
      return apply_deal(state, event["value"], actor, event_id, history) if event["action"] == "deal"
      selection = selection_from_event(event)
      return false unless selection && actions_for_state(state, actor).include?(selection)

      player = player_key(state, actor)
      state[:action_number] += 1
      case selection["action"]
      when "draw"
        state[:reaction] = nil
        draw_card(state, player)
        state[:phase] = :playing
        add_history(history, event_id, player, :draw, _("%{player} drew a card.") % { player: participant_name(player) })
      when "dirty_trick"
        apply_dirty_trick(state, selection, player, event_id, history)
      when "discard"
        state[:reaction] = nil
        card = selection["card"]
        state[:hands][player].delete(card)
        state[:discard] << card
        add_history(history, event_id, player, :discard, _("%{player} discarded %{card}.") % {
          player: participant_name(player), card: card_label(card)
        })
        begin_turn(state, next_player(state, player))
      when "play"
        apply_card(state, selection, player, event_id, history)
      end
      finish_round(state, event_id, history) if round_over?(state)
      true
    end

    def apply_deal(state, value, actor, event_id, history)
      return false unless same_user?(actor, state[:players].first)
      return false unless [:awaiting_deal, :round_complete].include?(state[:phase])
      return false if options_error(state[:options], player_count: state[:players].length)
      fields = value.to_s.split("|", -1)
      return false unless fields.length == 2 && fields[0] == (state[:round] + 1).to_s && /\A[0-9a-f]{32}\z/.match?(fields[1])
      assignment = team_assignment(state[:options], players: state[:players])
      return false if assignment && !assignment.valid?

      state[:round] += 1
      state[:seed] = fields[1]
      state[:draw_pile] = GameRoomRandom.shuffle(deck_for(state[:options]), random: Random.new(state[:seed].to_i(16)))
      state[:hands] = state[:players].to_h { |player| [player, []] }
      first_seat = (state[:round] - 1) % state[:players].length
      6.times do
        state[:players].length.times do |offset|
          player = state[:players][(first_seat + offset) % state[:players].length]
          state[:hands][player] << state[:draw_pile].shift
        end
      end
      state[:tracks] = Array.new(state[:scores].length) { fresh_track }
      state[:discard] = []
      state[:spent] = []
      state[:recycle_count] = 0
      state[:action_number] = 0
      state[:reaction] = nil
      state[:round_winner] = nil
      state[:round_scores] = []
      begin_turn(state, state[:players][first_seat])
      add_history(history, event_id, actor, :deal, _("Round %{round}. Six cards dealt to each player.") % { round: state[:round] })
      true
    end

    def deck_for(options)
      error = options_error(options)
      raise ArgumentError, error if error
      deck_counts_for(options).flat_map do |type, count|
        Array.new(count) { |copy| "#{type}:#{copy + 1}" }
      end
    end

    def actions_for_state(state, actor)
      return [] unless state && [:awaiting_draw, :playing].include?(state[:phase])
      player = player_key(state, actor)
      return [] unless player
      actions = dirty_trick_actions(state, player)
      return actions unless same_user?(state[:current_player], player)
      return actions + [{ "kind" => "command", "action" => "draw" }] if state[:phase] == :awaiting_draw

      hand_for(state, player).each do |card|
        type = card_type(card)
        if HAZARDS.include?(type)
          state[:tracks].each_index do |unit|
            next unless hazard_allowed?(state, player, type, unit)
            target = state[:seats].index(unit)
            actions << { "kind" => "card", "action" => "play", "card" => card, "target" => target.to_s }
          end
        elsif type == "instant_repair"
          repairable_problems(state, player).each do |problem|
            actions << { "kind" => "card", "action" => "play", "card" => card, "problem" => problem }
          end
        elsif own_card_allowed?(state, player, type)
          actions << { "kind" => "card", "action" => "play", "card" => card }
        end
        actions << { "kind" => "card", "action" => "discard", "card" => card }
      end
      actions
    end

    def dirty_trick_actions(state, actor)
      reaction = state[:reaction]
      return [] unless reaction && [:awaiting_draw, :playing].include?(state[:phase])
      unit = unit_for(state, actor)
      return [] unless unit == reaction[:unit]

      hand_for(state, actor).filter_map do |card|
        next unless card_type(card) == PROTECTION[reaction[:hazard]]
        next if state[:tracks][unit][:safeties].include?(card_type(card))
        { "kind" => "card", "action" => "dirty_trick", "card" => card, "reaction" => reaction[:token] }
      end
    end

    def hazard_allowed?(state, actor, hazard, target)
      return false if unit_for(state, actor) == target
      track = state[:tracks][target]
      return false if track[:safeties].include?(PROTECTION[hazard])
      return !track[:speed_limit] if hazard == "speed_limit"
      return state[:options]["counterflow"] && !track[:counterflow] if hazard == "counterflow"
      return false if track[:hazards].include?(hazard)
      state[:options]["accumulate_hazards"] || track[:moving]
    end

    def own_card_allowed?(state, actor, type)
      track = state[:tracks][unit_for(state, actor)]
      if DISTANCES.include?(type)
        return false unless track[:moving] && track[:hazards].empty?
        return false if track[:speed_limit] && type.to_i > 50
        return false if type == "200" && track[:two_hundreds] >= 2
        return track[:counterflow] || track[:miles] + type.to_i <= 1000
      end
      return !track[:safeties].include?(type) if SAFETIES.include?(type)
      return !track[:moving] && (track[:hazards] - ["stop"]).empty? if type == "go"
      return track[:speed_limit] if type == "end_limit"
      return state[:options]["counterflow"] && track[:counterflow] if type == "end_counterflow"
      track[:hazards].include?(REMEDIES[type])
    end

    def apply_card(state, selection, player, event_id, history)
      state[:reaction] = nil
      card = selection["card"]
      type = card_type(card)
      unit = unit_for(state, player)
      track = state[:tracks][unit]
      state[:hands][player].delete(card)
      state[:spent] << card
      if HAZARDS.include?(type)
        target = state[:seats][selection["target"].to_i]
        target_track = state[:tracks][target]
        state[:reaction] = { token: "#{state[:round]}:#{state[:action_number]}", unit: target,
          hazard: type, before: Marshal.load(Marshal.dump(target_track)) }
        if type == "speed_limit"
          target_track[:speed_limit] = true
        elsif type == "counterflow"
          target_track[:counterflow] = true
        else
          target_track[:hazards] << type
          target_track[:moving] = false
        end
        text = _("%{player} played %{card} against %{target}.") % {
          player: participant_name(player), card: card_label(card), target: unit_label(state, target)
        }
      elsif type == "instant_repair"
        problem = selection.fetch("problem")
        remove_problem(track, problem)
        text = _("%{player} used %{card} to remove %{problem}.") % {
          player: participant_name(player), card: card_label(card), problem: repair_problem_label(problem)
        }
      else
        apply_own_card(track, type)
        text = if DISTANCES.include?(type)
          _("%{player} played %{card}, now at %{miles} miles.") % {
            player: participant_name(player), card: card_label(card), miles: track[:miles]
          }
        else
          _("%{player} played %{card}.") % { player: participant_name(player), card: card_label(card) }
        end
      end
      add_history(history, event_id, player, :play, text)
      begin_turn(state, SAFETIES.include?(type) ? player : next_player(state, player))
    end

    def apply_own_card(track, type)
      if DISTANCES.include?(type)
        distance = track[:counterflow] ? -type.to_i : type.to_i
        track[:miles] = [track[:miles] + distance, 0].max
        track[:two_hundreds] += 1 if type == "200"
      elsif SAFETIES.include?(type)
        apply_safety(track, type)
      elsif type == "go"
        track[:hazards].delete("stop")
        track[:moving] = true
      elsif type == "end_limit"
        track[:speed_limit] = false
      elsif type == "end_counterflow"
        track[:counterflow] = false if track.key?(:counterflow)
      else
        remove_problem(track, REMEDIES.fetch(type))
      end
    end

    def repairable_problems(state, actor)
      return [] unless state[:options]["include_instant_repairs"]
      track = state[:tracks][unit_for(state, actor)]
      problems = track[:hazards].dup
      problems << "go" if !track[:moving] && problems.empty?
      problems << "speed_limit" if track[:speed_limit]
      problems << "counterflow" if track[:counterflow]
      problems
    end

    def remove_problem(track, problem)
      case problem
      when "speed_limit"
        track[:speed_limit] = false
      when "counterflow"
        track[:counterflow] = false if track.key?(:counterflow)
      else
        track[:hazards].delete(problem)
        track[:moving] = track[:hazards].empty? &&
          (%w[stop go].include?(problem) || track[:safeties].include?("right_of_way"))
      end
    end

    def apply_safety(track, type)
      track[:safeties] << type
      track[:hazards].reject! { |hazard| PROTECTION[hazard] == type }
      track[:speed_limit] = false if type == "right_of_way"
      track[:counterflow] = false if type == "driving_ace" && track.key?(:counterflow)
      track[:moving] = true if track[:hazards].empty? && track[:safeties].include?("right_of_way")
    end

    def apply_dirty_trick(state, selection, player, event_id, history)
      reaction = state[:reaction]
      unit = reaction[:unit]
      state[:tracks][unit] = reaction[:before]
      track = state[:tracks][unit]
      card = selection["card"]
      state[:hands][player].delete(card)
      state[:spent] << card
      apply_safety(track, card_type(card))
      track[:dirty_tricks] += 1
      state[:reaction] = nil
      draw_card(state, player) if draw_available?(state)
      begin_turn(state, player)
      add_history(history, event_id, player, :dirty_trick, _("%{player} played %{card}: dirty trick! 300 bonus points and an extra turn.") % {
        player: participant_name(player), card: card_label(card)
      })
    end

    def draw_available?(state)
      !state[:draw_pile].empty? || (state[:options]["recycle_discard"] && !state[:discard].empty?)
    end

    def draw_card(state, player)
      if state[:draw_pile].empty? && state[:options]["recycle_discard"] && !state[:discard].empty?
        state[:recycle_count] += 1
        state[:draw_pile] = GameRoomRandom.shuffle(state[:discard],
          random: Random.new(state[:seed].to_i(16) + state[:recycle_count]))
        state[:discard] = []
      end
      card = state[:draw_pile].shift
      state[:hands][player] << card if card
    end

    def begin_turn(state, player)
      state[:current_player] = player
      state[:phase] = draw_available?(state) ? :awaiting_draw : :playing
    end

    def round_over?(state)
      state[:tracks].any? { |track| track[:miles] == 1000 } || state[:hands].values.any?(&:empty?)
    end

    def round_points(track)
      track[:miles] + track[:safeties].length * 100 + track[:dirty_tricks] * 300
    end

    def finish_round(state, event_id, history)
      winner = state[:tracks].index { |track| track[:miles] == 1000 }
      points = state[:tracks].map { |track| round_points(track) }
      if winner
        points[winner] += 300
        points[winner] += 300 if state[:draw_pile].empty?
        points[winner] += 300 if state[:tracks][winner][:safeties].length == 4
        points[winner] += 500 if state[:tracks].each_with_index.all? { |track, unit| unit == winner || track[:miles] == 0 }
      end
      points.each_with_index { |score, unit| state[:scores][unit] += score }
      state[:round_scores] = points
      state[:round_winner] = winner
      state[:phase] = :round_complete
      state[:current_player] = nil
      state[:reaction] = nil
      text = winner ? _("%{player} reached exactly 1000 miles and won the round.") % { player: unit_label(state, winner) } :
        _("The round is over: a player has no cards left.")
      add_history(history, event_id, nil, :round_result, text)
      points.each_with_index do |score, unit|
        add_history(history, event_id, nil, :score, _("%{player}: %{points} points this round; total %{total}.") % {
          player: unit_label(state, unit), points: score, total: state[:scores][unit]
        })
      end
      highest = state[:scores].max
      return if highest < state[:options]["target_score"]
      leaders = state[:scores].each_index.select { |unit| state[:scores][unit] == highest }
      return if leaders.length > 1

      unit = leaders.first
      state[:winner] = state[:teams] ? "team:#{unit}" : state[:players][state[:seats].index(unit)]
      state[:phase] = :finished
    end

    def normalize_selection(selection)
      return nil unless selection.respond_to?(:[])
      kind = selection["kind"].to_s
      action = selection["action"].to_s
      if kind == "card" && action == "select"
        fields = selection["card"].to_s.split("|", -1)
        return nil unless fields.length == 3
        action, card, detail = fields
        candidate = { "kind" => "card", "action" => action, "card" => card }
        if action == "play" && !detail.empty?
          candidate[card_type(card) == "instant_repair" ? "problem" : "target"] = detail
        end
        candidate["reaction"] = detail if action == "dirty_trick"
        return nil if action == "discard" && !detail.empty?
        return candidate
      end
      return { "kind" => "command", "action" => "draw" } if kind == "command" && action == "draw"
      return nil unless kind == "card" && %w[play discard dirty_trick].include?(action)
      candidate = { "kind" => kind, "action" => action, "card" => selection["card"].to_s }
      candidate["target"] = selection["target"].to_s if action == "play" && selection["target"] != nil
      candidate["problem"] = selection["problem"].to_s if action == "play" && selection["problem"] != nil
      candidate["reaction"] = selection["reaction"].to_s if action == "dirty_trick"
      candidate
    end

    def action_value(action)
      return "" if action["action"] == "draw"
      return action["card"] if action["action"] == "discard"
      [action["card"], action["target"] || action["problem"] || action["reaction"]].join("|")
    end

    def selection_from_event(event)
      action = event["action"]
      value = event["value"].to_s
      return value.empty? ? { "kind" => "command", "action" => "draw" } : nil if action == "draw"
      return { "kind" => "card", "action" => "discard", "card" => value } if action == "discard"
      return nil unless %w[play dirty_trick].include?(action)
      normalize_selection({ "kind" => "card", "action" => "select", "card" => "#{action}|#{value}" })
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def hand_for(state, actor)
      state[:hands].fetch(player_key(state, actor), [])
    end

    def unit_for(state, actor)
      seat = state[:players].index { |player| same_user?(player, actor) }
      seat && state[:seats][seat]
    end

    def next_player(state, player)
      seat = state[:players].index(player)
      state[:players][(seat + 1) % state[:players].length]
    end

    def card_type(card)
      card.to_s.split(":", 2).first
    end

    def add_history(history, event_id, actor, kind, text)
      history << HistoryEntry.new(key: "miles:#{event_id}:#{history.length}", event_id: event_id,
        actor: actor, kind: kind, text: GameRoomContent.utf8(text))
    end
  end
end
