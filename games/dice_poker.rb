require_relative "base"
require_relative "base/round_tournament"
require_relative "../lib/game_bots"
require_relative "../lib/dice_poker_strategy"
require_relative "../lib/blackjack_auction"

module GameRoomGames
  using GameRoomLocalization::Translations

  class DicePoker < Base
    include PublicHistoryAnnouncements
    include BlackjackAuction
    include RoundTournament
    CHIP_OPTIONS = [
      OptionDefinition.new(key: "scoring", label: _("Dice poker scoring"), kind: :choice, default: "points", choices: [
        OptionChoice.new(value: "points", label: _("Points, without betting")), OptionChoice.new(value: "chips", label: _("Chips with betting before and after throws"))]),
      OptionDefinition.new(key: "starting_chips", label: _("Starting chips"), kind: :integer, default: 1000, visible_if: {"scoring"=>"chips"}),
      OptionDefinition.new(key: "stake", label: _("Opening contribution"), kind: :integer, default: 10, visible_if: {"scoring"=>"chips"})].freeze
    GameRoomServerRandom.register("dice_poker", ["roll"])

    def id; "dice_poker"; end
    def name; _("Dice poker"); end
    def short_description; _("Keep useful dice, reroll the others and make the strongest poker combination."); end
    def minimum_players; 2; end
    def maximum_players; 8; end
    def supports_bots?; true; end
    def bot_strategy; @bot_strategy ||= GameRoomBots::HeuristicStrategy.new; end
    def rule_sections; generated_rule_sections; end
    def notification_option_keys(_options); %w[variant]; end
    def player_spatial_audio?; true; end

    def option_definitions
      [OptionDefinition.new(key: "variant", label: _("Variant"), kind: :choice, default: "classic", choices: [
        OptionChoice.new(value: "classic", label: _("Poker dice with straights; sixes high")),
        OptionChoice.new(value: "no_straights", label: _("No straights; sixes high")),
        OptionChoice.new(value: "aces_high", label: _("No straights; ones are aces and rank highest"))
      ]),
        OptionDefinition.new(key: "throws", label: _("Maximum throws per turn"), kind: :choice, default: 3, choices: [
          OptionChoice.new(value: 3, label: _("Three throws")), OptionChoice.new(value: 2, label: _("Two throws"))]),
        OptionDefinition.new(key: "opener_limit", label: _("The opener's throws limit the other players"), kind: :boolean, default: false),
        OptionDefinition.new(key: "round_limit", label: _("Number of rounds"), kind: :integer, default: 3)] + CHIP_OPTIONS
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      rounds = values["round_limit"]
      return _("Choose from 1 to 20 rounds.") unless rounds.is_a?(Integer) && rounds.between?(1, 20)
      if chip_rules?(values)
        return _("Starting chips must be from 10 to 10000.") unless values["starting_chips"].is_a?(Integer) && values["starting_chips"].between?(10,10000)
        return _("The stake must be positive and cannot exceed starting chips.") unless values["stake"].is_a?(Integer) && values["stake"].between?(1,values["starting_chips"])
      end
      nil
    end

    def normalize_options(values)
      result = super
      unless chip_rules?(result)
        CHIP_OPTIONS.each { |definition| result.delete(definition.key) if result[definition.key] == definition.default }
      end
      result
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = {players: players, options: options_from_json(session["options"]), round: 1, turn: 0,
        dice: Array.new(5), rolls: 0, hands: {}, budget: nil, scores: players.to_h { |p| [p, 0] },
        current_player: players.first, winner: nil, draw: false, phase: :playing}
      if chip_rules?(state[:options])
        state.merge!(phase: :awaiting_ante, chips: players.to_h { |p| [p,state[:options]["starting_chips"]] }, eliminated: [], pot: 0)
      end
      enable_round_tournament(state, session)
      accepted, history, seen = [], [starting_history(players)], {}
      events.each do |event|
        break if state[:phase] == :finished
        event_id = repository.event_id(event)
        next if seen[event_id]
        if event["action"] == "tournament_elimination"
          next unless apply_round_tournament_elimination(state, event, event_id, history) { restart_dice_round(state) }
        else
          next unless same_user?(repository.actor_of(event, session), state[:current_player])
          next unless apply_event(state, event, event_id, history)
        end
        accepted << event
        seen[event_id] = true
      end
      Replay.new(players: players, current_player: state[:current_player], state: state, board: nil,
        winner: state[:winner], draw: state[:draw], history: history, accepted_events: accepted)
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || !same_user?(replay.current_player, actor)
      state = replay.state
      return auction_actions(replay,actor) if state[:phase] == :betting
      return [] unless state[:phase] == :playing
      return [{"kind" => "dice", "action" => "roll"}] if state[:rolls] == 0
      actions = [{"kind" => "dice", "action" => "score", "category" => "stand"}]
      if state[:rolls] < throw_limit(state)
        1.upto(31) { |mask| actions << {"kind" => "dice", "action" => "roll", "die_ids" => (0...5).select { |i| mask[i] == 1 }.map { |i| "d#{i}" }.join(",")} }
      end
      actions
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      return [:not_your_turn, nil] unless same_user?(replay.current_player, actor)
      state = replay.state
      action = selection["action"]
      if action == "ante" && state[:phase] == :awaiting_ante && same_user?(actor,replay.players.first)
        return [:ok,event_plan("ante",state[:round].to_s)]
      end
      return auction_plan(selection,replay) if state[:phase] == :betting
      return [:invalid,nil] unless state[:phase] == :playing
      if action == "roll"
        return [:roll_limit, nil] if state[:rolls] >= throw_limit(state)
        return [:invalid, nil] unless context&.random_source
        indices = state[:rolls] == 0 ? (0...5).to_a : die_indices(selection["die_ids"])
        return [:choose_dice, nil] if indices.empty?
        keep = state[:dice].each_with_index.filter_map { |value, index| value unless indices.include?(index) }
        if context.server_random
          command = GameRoomServerRandom.command(action: "roll", count: indices.size, sides: 6, keep: keep, sort: true)
          return [:ok, ActionPlan.new(events: [command])]
        end
        values = keep + context.random_source.roll(count: indices.size, sides: 6).values
        [:ok, event_plan("roll", values.sort.join(","))]
      elsif action == "score" && selection["category"] == "stand"
        return [:roll_first, nil] if state[:rolls] == 0
        [:ok, event_plan("stand", state[:round].to_s)]
      else
        [:invalid, nil]
      end
    end

    def surface_spec(replay, viewer)
      state = replay.state
      return auction_surface(replay,viewer) if state[:phase] == :betting
      header = GameRoomContent.utf8(_("Dice poker: round %{round} of %{total}; throw %{roll} of %{limit}.") % {
        round: state[:round], total: state[:options]["round_limit"], roll: state[:rolls], limit: throw_limit(state)})
      unless state[:phase] == :playing && !replay.finished? && same_user?(replay.current_player, viewer)
        return GameSurfaces::PawnTrackSpec.new(id: "dice_poker_status", header: header,
          items: [GameSurfaces::PawnTrackItem.new(id: "status", label: GameRoomContent.utf8(replay.finished? ? result_text(replay) : current_turn_shortcut_text(replay, viewer)))])
      end
      choices = state[:rolls] == 0 ? [] : [GameSurfaces::ScoreChoice.new(id: "stand", value: "stand",
        label: GameRoomContent.utf8(_("Keep this hand: %{hand}") % {hand: hand_name(state[:dice], state[:options]["variant"])}))]
      GameSurfaces::RollAndScoreSpec.new(id: "dice_poker", header: header,
        dice: state[:dice].each_with_index.map { |value, index| GameSurfaces::Die.new(id: "d#{index}", value: value, sides: 6, held: true, enabled: true) },
        categories: choices, can_roll: state[:rolls] < throw_limit(state), force_categories: state[:rolls] >= throw_limit(state),
        empty_label: GameRoomContent.utf8(_("Roll the dice first")), roll_number: state[:rolls])
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = [announcement_shortcut(key: "s", label: _("read the scores"), message: score_text(replay.state))]
      return shortcuts + auction_shortcuts(replay,viewer) if replay.state[:phase] == :betting
      state = replay.state
      return shortcuts unless state[:phase] == :playing && !replay.finished? && same_user?(replay.current_player, viewer)
      if state[:rolls].positive? && state[:rolls] < throw_limit(state)
        1.upto(6) do |value|
          shortcuts << surface_shortcut(key: value.to_s, label: _("select another die showing %{value}") % {value: value}, command: "select_die", payload: {"value" => value})
          shortcuts << surface_shortcut(key: value.to_s, modifiers: [:shift], label: _("keep another die showing %{value}") % {value: value}, command: "unselect_die", payload: {"value" => value})
        end
      end
      shortcuts << surface_shortcut(key: "space", label: _("read the dice and their selection state"), command: "announce_dice")
      shortcuts << GameShortcut.new(key: "k", label: _("keep the current poker dice hand"), kind: :action,
        action_kind: "dice", action_name: "score", payload: {"category" => "stand"}) if replay.state[:rolls] > 0
      shortcuts
    end

    def participant_scores(replay); (replay.state[:chips] || replay.state[:scores]).dup; end
    def eliminated_from_game?(replay,viewer)
      super || GameRoomParticipants.includes?(replay&.state&.fetch(:eliminated, []).to_a, viewer)
    end
    def automatic_action(replay,actor,context:nil)
      {"kind"=>"command","action"=>"ante"} if !replay.finished? && replay.state[:phase] == :awaiting_ante && same_user?(actor,replay.players.first)
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      if state[:phase] == :betting
        return auction_opening_bot_score(state, action) unless state[:betting_stage] == 2
        return showdown_bot_score(state, action)
      end
      return 10 if state[:rolls] == 0

      variant = state[:options]["variant"]
      order = state[:round_order] || tournament_contenders(state)
      completed = state[:hands].transform_values { |dice| GameRoomDicePokerHands.rank(dice, variant) }
      pending = order.size - state[:turn] - 1
      split_ties = chip_rules?(state[:options])
      pots = auction_pots(state) if split_ties
      key = [variant, completed, pending, split_ties, actor, pots]
      if @bot_plan_key != key
        utility = if split_ties
          GameRoomDicePokerStrategy.pot_value(variant, pots, actor, completed)
        else
          GameRoomDicePokerStrategy.contest_value(variant, completed.values, pending, split_ties: false)
        end
        @bot_plan_key, @bot_plan = key, GameRoomDicePokerStrategy::Plan.new(variant, utility)
      end
      return @bot_plan.stand(state[:dice].sort) + 1e-9 if action["action"] == "score"

      indices = die_indices(action["die_ids"])
      keep = state[:dice].each_with_index.filter_map { |value, index| value unless indices.include?(index) }.sort
      @bot_plan.roll(keep, throw_limit(state) - state[:rolls])
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      cues = auction_sound_cues(event, history)
      cues << "roll" if event["action"] == "roll"
      cues << "play" if event["action"] == "stand"
      cues
    end

    private

    def chip_rules?(options); GameRoomOptionValues.read(CHIP_OPTIONS.first,options) == "chips"; end
    def auction_unit; 1; end

    def showdown_bot_score(state, action)
      return 2 if action["action"] == "check"
      return 1 if action["action"] == "fold"
      return -1 unless action["action"] == "call"

      player, paid = state[:current_player], action["amount"]
      # Evaluate only layers the bot can actually win. A strong short-stacked
      # hand must not make the bot abandon a winning side pot.
      original = state[:auction][:contributions]
      contributions = original.merge(player => original.fetch(player) + paid)
      hands = state[:hands].transform_values { |dice| GameRoomDicePokerHands.rank(dice, state[:options]["variant"]) }
      share = auction_pots(state, contributions: contributions).sum do |pot|
        eligible = pot[:eligible]
        next 0 unless eligible.include?(player)
        best = eligible.map { |person| hands.fetch(person) }.max
        next 0 unless hands[player] == best
        # The exact odd chip is not needed to decide whether to match.
        pot[:amount] / eligible.count { |person| hands[person] == best }
      end
      share > paid ? 2 : 0
    end
    def add_history(history,event_id,actor,kind,text)
      history << HistoryEntry.new(key:"#{kind}:#{event_id}:#{history.size}",event_id:event_id,actor:actor,kind:kind,text:text)
    end

    def complete_auction(state,event_id,history)
      if auction_contenders(state).one? || state[:betting_stage] == 2
        settle_chip_round(state,event_id,history)
      else
        state[:round_order] = auction_contenders(state)
        state.merge!(phase: :playing,current_player:state[:round_order].first,dice:Array.new(5),rolls:0,turn:0)
      end
    end

    def settle_chip_round(state,event_id,history)
      auction_pots(state).each do |pot|
        eligible = pot[:eligible]
        if eligible.empty? || pot[:contributors].one?
          pot[:contributors].each { |p| state[:chips][p] += pot[:slice] }
          next
        end
        ranks = eligible.to_h { |p| [p,eligible.one? ? [0] : GameRoomDicePokerHands.rank(state[:hands].fetch(p),state[:options]["variant"])] }
        winners = eligible.select { |p| ranks[p] == ranks.values.max }
        share,odd = pot[:amount].divmod(winners.size)
        winners.each_with_index { |p,i| state[:chips][p] += share + (i < odd ? 1 : 0) }
        add_history(history, event_id, "", :pot, dice_pot_result(winners, pot[:amount]))
      end
      state[:pot] = 0
      state[:eliminated] = state[:players].select { |p| state[:chips][p] == 0 }
      state[:players].each { |p| add_history(history,event_id,p,:settlement,_("%{player} has %{chips} chips.") % {player:participant_name(p),chips:state[:chips][p]}) }
      record_tournament_round(state, event_id)
      if state[:round] == state[:options]["round_limit"] || tournament_contenders(state).size < 2
        contenders = tournament_remaining_players(state)
        best = contenders.map { |player| state[:chips].fetch(player) }.max
        winners = contenders.select { |player| state[:chips][player] == best }
        record_tournament_winners(state, winners)
        state.merge!(phase: :finished, current_player: nil, winner: winners.one? ? winners.first : nil, draw: !winners.one?)
        history << result_history(event_id:event_id,winner:state[:winner],draw:state[:draw])
      else
        state.delete(:auction)
        state.merge!(phase: :awaiting_ante,round:state[:round]+1,hands:{},budget:nil,dice:Array.new(5),rolls:0,turn:0,current_player:state[:players].first)
      end
    end

    def tournament_round_scores(state)
      state[:chips] || state[:scores]
    end

    def point_round_order(state)
      state[:players].rotate((state[:round] - 1) % state[:players].size) & tournament_contenders(state)
    end

    def restart_dice_round(state)
      state.merge!(dice: Array.new(5), rolls: 0, hands: {}, budget: nil, turn: 0)
      if state[:chips]
        state[:restart_opener] = state[:round_opener] if state[:phase] != :awaiting_ante
        refund_interrupted_auction(state)
        state.merge!(phase: :awaiting_ante, current_player: state[:players].first)
      else
        state[:current_player] = point_round_order(state).first
      end
    end

    def throw_limit(state); state[:budget] || state[:options]["throws"].to_i; end
    def die_indices(text)
      return [] unless text.is_a?(String) && text.match?(/\Ad[0-4](?:,d[0-4])*\z/)
      indices = text.split(",").map { |value| value[1].to_i }
      indices.uniq.size == indices.size ? indices.sort : []
    end

    def hand_name(dice, variant)
      [_("High card"), _("One pair"), _("Two pairs"), _("Three of a kind"), _("Straight"), _("Full house"), _("Four of a kind"), _("Five of a kind")].fetch(GameRoomDicePokerHands.rank(dice, variant).first)
    end

    def score_text(state)
      return state[:players].map { |p| _("%{player} has %{chips} chips.") % {player:participant_name(p),chips:state[:chips][p]} }.join(" ") if state[:chips]
      state[:players].map do |player|
        points = state[:scores][player]
        n_("%{player}: %{points} point", "%{player}: %{points} points", points) % {player: participant_name(player), points: points}
      end.join(". ")
    end

    def apply_event(state, event, event_id, history)
      player, value = state[:current_player], event["value"].to_s
      if event["action"] == "ante"
        return false unless state[:phase] == :awaiting_ante && value == state[:round].to_s
        state[:betting_stage] = 1
        restart_opener = state.delete(:restart_opener)
        offset = if restart_opener
          state[:players].index(restart_opener)
        elsif state[:round_opener]
          state[:players].index(state[:round_opener]) + 1
        else
          0
        end
        order = state[:players].rotate(offset) & tournament_contenders(state)
        state[:round_opener] = order.first
        start_auction(state,order,event_id,history)
      elsif event["action"] == "bet"
        return apply_auction(state,event,player,event_id,history)
      elsif event["action"] == "roll"
        return false unless state[:phase] == :playing
        return false if state[:rolls] >= throw_limit(state) || !value.match?(/\A[1-6](?:,[1-6]){4}\z/)
        dice = value.split(",").map(&:to_i)
        return false unless dice == dice.sort
        if (request = event['__server_random'])
          count, keep = request.values_at('count', 'keep')
          return false unless count.is_a?(Integer) && count.between?(1,5) && keep.is_a?(Array) && count + keep.size == 5
          available = state[:rolls] == 0 ? [] : state[:dice].dup
          return false unless keep.all? { |face| index = available.index(face); index && available.delete_at(index) }
          return false unless GameRoomServerRandom.valid_dice_event?(event, count: count, sides: 6, keep: keep, sort: true)
        end
        state[:dice], state[:rolls] = dice, state[:rolls] + 1
        history << HistoryEntry.new(key: "roll:#{event_id}", event_id: event_id, actor: player, kind: :roll,
          text: _("%{player} rolls %{dice}: %{hand}.") % {player: participant_name(player), dice: dice.join(", "), hand: hand_name(dice, state[:options]["variant"])})
      elsif event["action"] == "stand"
        return false unless state[:phase] == :playing && state[:rolls] > 0 && value == state[:round].to_s
        state[:hands][player] = state[:dice].dup
        add_history(history, event_id, player, :stand, _("%{player} keeps the hand: %{hand}.") % {
          player: participant_name(player), hand: hand_name(state[:dice], state[:options]["variant"])})
        state[:budget] = state[:rolls] if state[:turn] == 0 && state[:options]["opener_limit"]
        state[:turn] += 1
        if state[:chips]
          if state[:hands].size == state[:round_order].size
            state[:betting_stage] = 2
            continue_auction(state,event_id,history)
          else
            state[:current_player] = state[:round_order][state[:hands].size]
          end
          state[:dice],state[:rolls] = Array.new(5),0 unless state[:phase] == :finished
          return true
        end
        settle_round(state, event_id, history) if state[:turn] == tournament_contenders(state).size
        unless state[:phase] == :finished
          state[:current_player] = point_round_order(state).fetch(state[:turn])
          state[:dice], state[:rolls] = Array.new(5), 0
        end
      else
        return false
      end
      true
    end

    def settle_round(state, event_id, history)
      ranks = state[:hands].transform_values { |dice| GameRoomDicePokerHands.rank(dice, state[:options]["variant"]) }
      winners = ranks.keys.select { |player| ranks[player] == ranks.values.max }
      winners.each { |player| state[:scores][player] += 1 }
      hand = hand_name(state[:hands].fetch(winners.first), state[:options]["variant"])
      text = if winners.one?
        _("Round %{round}: %{player} wins and earns one point. Winning hand: %{hand}.") % {
          round: state[:round], player: participant_name(winners.first), hand: hand}
      else
        _("Round %{round}: %{players} tie. Each earns one point. Winning hand: %{hand}.") % {
          round: state[:round], players: winners.map { |player| participant_name(player) }.join(", "), hand: hand}
      end
      add_history(history, event_id, "", :round, text)
      record_tournament_round(state, event_id)
      if state[:round] == state[:options]["round_limit"]
        contenders = tournament_contenders(state)
        best = contenders.map { |player| state[:scores].fetch(player) }.max
        leaders = contenders.select { |player| state[:scores][player] == best }
        record_tournament_winners(state, leaders)
        state.merge!(phase: :finished, current_player: nil, winner: leaders.one? ? leaders.first : nil, draw: !leaders.one?)
        history << result_history(event_id: event_id, winner: state[:winner], draw: state[:draw])
      else
        state.merge!(round: state[:round] + 1, turn: 0, hands: {}, budget: nil)
      end
    end
  end
end

require_relative "generated/rulebooks/dice_poker"
