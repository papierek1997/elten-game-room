module GameRoomGames
  using GameRoomLocalization::Translations

  class LiarsDice
    def prepare_view(replay, viewer, context: nil)
      @private_view = nil
      player = player_key(replay.state, viewer)
      return unless player && replay.state[:counts][player] > 0
      dice = GameRoomLiarsDiceSecrets.dice(replay.state, player, context)
      @private_view = [view_key(replay.state, player), dice] if dice
    rescue HiddenSubmissions::StorageError
      @private_view = nil
    end

    def surface_spec(replay, viewer)
      state = replay.state
      items = [GameSurfaces::PawnTrackItem.new(id: "status", label: GameRoomContent.utf8(status_text(replay, viewer)))]
      if state[:phase] == :bidding && same_user?(state[:current_player], viewer)
        minimum_bids(state, viewer).each do |quantity, face|
          items << command_item("bid:#{face}", bid_label(quantity, face), selection(state, "bid").merge("quantity"=>quantity, "face"=>face))
        end
        items << command_item("challenge", _("Call bluff"), selection(state, "challenge")) if state[:bid]
      end
      if state[:phase] == :bidding && GameRoomParticipants.includes?(active_actors(replay), viewer) && exact_allowed?(state, viewer)
        items << command_item("exact", _("Call exactly"), selection(state, "exact"))
      end
      GameSurfaces::PawnTrackSpec.new(id: "liars_dice", header: GameRoomContent.utf8(name), items: items)
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      shortcuts = [announcement_shortcut(key: "v", label: _("read your hidden dice"), message: own_dice_text(state, viewer)),
        announcement_shortcut(key: "l", label: _("read the current dice bid"), message: state[:bid] ? bid_label(state[:bid][:quantity], state[:bid][:face]) : _("There is no bid yet."))]
      return shortcuts unless state[:phase] == :bidding && GameRoomParticipants.includes?(active_actors(replay), viewer)
      if same_user?(state[:current_player], viewer)
        bids = minimum_bids(state, viewer)
        preferred = bids.find { |_, face| face == state[:bid]&.fetch(:face) } || bids.first
        if preferred
          faces = [preferred.last] + bids.map(&:last).reject { |face| face == preferred.last }
          shortcuts << GameShortcut.new(key: "b", label: _("enter a dice bid"), kind: :form, prompt: _("Dice bid"),
          action_kind: "command", action_name: "bid", payload: {"round"=>state[:round], "bid_index"=>state[:bid_index]}, fields: [
            OptionDefinition.new(key: "quantity", label: _("Number of dice"), kind: :integer, default: preferred.first),
            OptionDefinition.new(key: "face", label: _("Die face"), kind: :choice, default: preferred.last,
              choices: faces.map { |face| OptionChoice.new(value: face, label: face.to_s) })])
        end
        shortcuts << GameShortcut.new(key: "k", label: _("call the previous bidder's bluff"), kind: :action,
          action_kind: "command", action_name: "challenge", payload: {"round"=>state[:round], "bid_index"=>state[:bid_index]}) if state[:bid]
      end
      if exact_allowed?(state, viewer)
        shortcuts << GameShortcut.new(key: "d", label: _("call the bid exactly right"), kind: :action,
          action_kind: "command", action_name: "exact", payload: {"round"=>state[:round], "bid_index"=>state[:bid_index]})
      end
      shortcuts
    end

    def current_turn_shortcut_text(replay, viewer)
      replay.finished? ? result_text(replay) : status_text(replay, viewer)
    end

    def bot_action_score(replay, actor, action, context: nil)
      return 0 unless replay.state[:phase] == :bidding
      state = replay.state
      cache = @bot_view
      unless cache && cache[:replay].equal?(replay) && cache[:actor] == actor && cache[:vault].equal?(context&.hidden_submissions) && cache[:session] == context&.session_id
        dice = GameRoomLiarsDiceSecrets.dice(state, actor, context)
        raise HiddenSubmissions::StorageError, "Bot's committed dice secret is unavailable" unless dice
        @bot_view = cache = {replay: replay, actor: actor, vault: context.hidden_submissions, session: context.session_id, dice: dice}
      end
      quantity, face = action["action"] == "bid" ? action.values_at("quantity", "face") : state[:bid].values_at(:quantity, :face)
      own = GameRoomLiarsDiceRules.count(cache[:dice], face, variant: state[:options]["variant"], palifico: state[:palifico])
      unknown = state[:counts].values.sum - cache[:dice].size
      probability = state[:options]["variant"] == "perudo" && !state[:palifico] && face != 1 ? 1.0/3 : 1.0/6
      exact, at_least = count_probabilities(quantity - own, unknown, probability)
      case action["action"]
      when "challenge" then (1 - at_least) * 150 - at_least * 80
      when "exact" then exact * 100 - (1 - exact) * 50
      else at_least * 80 - quantity * 0.1
      end
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      case event["action"]
      when "deal" then "roll"
      when "bid" then "play"
      when "challenge", "exact" then "buzzer"
      end
    end

    private

    def view_key(state, player); [state[:session_id], state[:round], state[:seed], player]; end
    def bid_label(quantity, face); _("%{quantity} dice showing %{face}") % {quantity: quantity, face: face}; end
    def minimum_bids(state, actor)
      (1..6).filter_map do |face|
        quantity = (1..state[:counts].values.sum).find { |count| bid_allowed?(state, count, face, actor) }
        [quantity, face] if quantity
      end
    end

    def own_dice_text(state, viewer)
      player = player_key(state, viewer)
      return _("You have no dice in this game.") unless player && state[:counts][player] > 0
      dice = @private_view && @private_view.first == view_key(state, player) ? @private_view.last : state[:reveals][player]
      dice ? _("Your dice: %{dice}.") % {dice: dice.join(", ")} : _("Your dice will be available after all players secure their rolls.")
    end

    def status_text(replay, viewer)
      state = replay.state
      return result_text(replay) if replay.finished?
      phase = case state[:phase]
      when :committing, :dealing then _("Securing hidden dice.")
      when :revealing then _("Revealing dice after a challenge.")
      else _("Bidder: %{player}.") % {player: participant_name(state[:current_player])}
      end
      bid = state[:bid] ? bid_label(state[:bid][:quantity], state[:bid][:face]) : _("There is no bid yet.")
      _("Round %{round}. %{phase} Current bid: %{bid}. %{dice}") % {round: state[:round], phase: phase, bid: bid, dice: own_dice_text(state, viewer)}
    end

    def command_item(id, label, data)
      GameSurfaces::PawnTrackItem.new(id: id, label: GameRoomContent.utf8(label), action: GameSurfaces::Action.from_h(data))
    end

    def count_probabilities(needed, count, probability)
      exact, at_least, term = 0.0, 0.0, (1 - probability) ** count
      0.upto(count) do |value|
        exact = term if value == needed
        at_least += term if value >= needed
        term *= (count - value).to_f / (value + 1) * probability / (1 - probability)
      end
      [exact, at_least]
    end
  end
end
