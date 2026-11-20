# frozen_string_literal: true

require_relative 'challenge_presentation'

module GameRoomGames
  using GameRoomLocalization::Translations

  class DuckRacing
    def rule_sections; generated_rule_sections; end
    def shortcut_features; []; end

    def square_name(square)
      case square
      when 1 then _("On the line")
      when 2 then _("Forest edge")
      when 3 then _("Front pond")
      when 4 then _("Left bank")
      when 5 then _("Diving board")
      when 6 then _("South bank")
      when 7, 20 then _("Ducklings' nest")
      when 8 then _("Shady water")
      when 9 then _("Reed path")
      when 10, 17 then _("In the pond")
      when 11, 21 then _("Water lilies")
      when 12, 15 then _("On the water")
      when 13 then _("Warm water")
      when 14 then _("Cosy nest")
      when 16 then _("Whirlpool")
      when 18 then _("Deep water")
      when 19 then _("Natural shelter")
      when 22 then _("North bank")
      when 23 then _("Paddling pool")
      when 24 then _("Off the water")
      when 25 then _("Right bank")
      when 26 then _("Resupplying area")
      when 27 then _("Sandbox")
      when 28 then _("Wooden zone")
      when 29 then _("Puddle of water")
      when 30 then _("Finish line")
      else raise ArgumentError, "Unknown race square"
      end
    end

    def challenge_name(kind)
      case kind
      when "rock_paper_scissors" then _("Rock, paper, scissors")
      when "dice_duel" then _("Dice duel")
      when "blackjack" then _("Twenty-one")
      when "risky_dice" then _("Risky dice")
      when "guess_number" then _("Guess the number")
      when "copy_number" then _("Copy the number")
      when "arithmetic" then _("Mental arithmetic")
      when "race_question" then _("Race question")
      when "numbered_balls" then _("Numbered balls")
      when "count_ducks" then _("Count the ducks")
      when "rhythm" then _("Repeat the rhythm")
      when "sound_order" then _("Order the sounds")
      when "simon" then _("Simon")
      when "sound_memory" then _("Sound pairs")
      when "hit_duck" then _("Hit the duck")
      when "quiz" then _("Quiz")
      when "audio_ball" then _("Audio Ball")
      when "axel_pong" then _("Axel Pong")
      else raise ArgumentError, "Unknown race challenge"
      end
    end

    def challenge_description(kind)
      case kind
      when "rock_paper_scissors" then _("Choose a sign to beat your opponent: rock beats scissors, scissors beat paper, and paper beats rock.")
      when "dice_duel" then _("Each player rolls once. The highest roll wins.")
      when "blackjack" then _("Draw cards to get as close to 21 as you can without going over.")
      when "risky_dice" then _("Keep rolling two dice to build your total, but stop before you go over 25.")
      when "guess_number" then _("Guess the hidden number in up to ten attempts, using higher-or-lower hints. The closest guess wins.")
      when "copy_number" then _("Be the first to type the displayed number correctly.")
      when "arithmetic" then _("Work out the calculation in your head and be the first to enter the correct answer.")
      when "race_question" then _("Be the first to answer a question about the current race, such as where a duck is or how many feathers it has.")
      when "numbered_balls" then _("Take turns choosing one, two or three balls from the front of the row. Collect the highest total, watching out for negative numbers.")
      when "count_ducks" then _("Count the quacks and be the first to enter the correct number.")
      when "rhythm" then _("Listen to a drum rhythm, then repeat it with F and J as accurately as you can.")
      when "sound_order" then _("Be the first to arrange eight notes from lowest to highest by swapping them in pairs.")
      when "simon" then _("Repeat a melody that gets longer each round. The player who remembers the longest sequence wins.")
      when "sound_memory" then _("Find matching sounds hidden under the digit keys. Remember what you hear and collect more pairs than your opponent.")
      when "hit_duck" then _("Listen for the duck's position and press the matching digit from 1 on the left to 9 on the right.")
      when "quiz" then _("Choose the correct answer from four options. Everyone who answers correctly earns feathers.")
      when "audio_ball" then _("Play for one point: recognize the ball by its sound, choose the right defense and send it back.")
      when "axel_pong" then _("Play for one point: move your racket left and right, defend your goal and get the ball past your opponent.")
      else raise ArgumentError, "Unknown race challenge"
      end
    end

    def card_name(type)
      case type
      when "mine" then _("Mine")
      when "interested_help" then _("Interested help")
      when "helix" then _("Helix")
      when "hand_switch" then _("Hand switch")
      when "yellowbelly_die" then _("Yellowbelly die")
      when "challenge" then _("Challenge")
      when "tar_stain" then _("Tar stain")
      when "soporific_pill" then _("Soporific pill")
      when "paid_service" then _("Paid service")
      when "opportunistic_die" then _("Opportunistic die")
      when "investment" then _("Investment")
      when "ejectable_seat" then _("Ejectable seat")
      when "withdrawal" then _("Withdrawal")
      when "super_glue" then _("Super glue")
      when "long_absence" then _("Long absence")
      when "detour" then _("Detour")
      when "guided_missile" then _("Guided missile")
      when "super_challenge" then _("Super challenge")
      when "winning_die" then _("Winning die")
      when "shortness_of_breath" then _("Shortness of breath")
      when "impulsion" then _("Impulsion")
      when "taste_for_risk" then _("Taste for risk")
      when "home_made_bomb" then _("Home made bomb")
      when "sandwich" then _("Sandwich")
      when "counter_current" then _("Counter-current")
      when "hand_mix" then _("Hand mix")
      when "card_rob" then _("Card rob")
      when "planified_deal" then _("Planified deal")
      when "repairing_rest" then _("Repairing rest")
      when "curiosity" then _("Curiosity")
      when "tiny_recoil" then _("Tiny recoil")
      when "good_draw" then _("Good draw")
      when "oil_stain" then _("Oil stain")
      when "die_normalizing" then _("Die normalizing")
      when "altruism" then _("Altruism")
      when "thick_die" then _("Thick die")
      when "golden_sleep" then _("Golden sleep")
      else raise ArgumentError, "Unknown race card"
      end
    end

    def card_description(type)
      card = Logic::Cards::BY_ID.fetch(type)
      # Describe who receives each effect, not a sequence of imperatives that
      # mistakenly tells the player to move themselves when targeting a rival.
      description = case type
      when 'mine' then _("Leave it on your square. The next duck to land there moves back 15 squares.")
      when 'interested_help' then _("Take 3 feathers from an opponent and move them forward 2 squares.")
      when 'helix' then _("Move yourself or another duck forward 4 squares.")
      when 'hand_switch' then _("Exchange all your cards with an opponent.")
      when 'yellowbelly_die' then _("An opponent rolls a three-sided die for their next 2 race rolls.")
      when 'challenge' then _("Challenge an opponent to a random two-player challenge.")
      when 'tar_stain' then _("Leave it on your square. Take 4 feathers from the next other duck to land there. Your own duck leaves the card in place.")
      when 'soporific_pill' then _("An opponent skips 3 turns.")
      when 'paid_service' then _("Take 4 feathers from an opponent and move them forward 3 squares.")
      when 'opportunistic_die' then _("Roll a ten-sided die for your next 2 race rolls.")
      when 'investment' then _("Receive 7 feathers and leave the card on your square. The next duck to land there moves forward 5 squares.")
      when 'ejectable_seat' then _("Leave it on your square. The next duck to land there moves 1 or 2 squares in a random direction.")
      when 'withdrawal' then _("Move yourself or another duck back 2 squares.")
      when 'super_glue' then _("Leave it on your square. The next duck to land there skips 3 turns.")
      when 'long_absence' then _("An opponent skips 2 turns.")
      when 'detour' then _("Leave it on your square. The next duck to land there moves back 4 squares.")
      when 'guided_missile' then _("Move an opponent back 10 squares.")
      when 'super_challenge' then _("Start a random challenge for all unfrozen ducks.")
      when 'winning_die' then _("Roll a twelve-sided die for your next 3 race rolls.")
      when 'shortness_of_breath' then _("Move yourself or another duck back 3 squares.")
      when 'impulsion' then _("Move yourself or another duck forward 2 squares.")
      when 'taste_for_risk' then _("Move between 1 and 10 squares in a random direction.")
      when 'home_made_bomb' then _("Move an opponent between 1 and 8 squares in a random direction.")
      when 'sandwich' then _("Receive 3 feathers and skip this turn.")
      when 'counter_current' then _("Leave it on your square. The next duck to land there moves back 3 squares.")
      when 'hand_mix' then _("Everyone passes all their cards to the next player.")
      when 'card_rob' then _("Take a random card from an opponent.")
      when 'planified_deal' then _("Leave it on your square. When a duck lands there, everyone draws a card.")
      when 'repairing_rest' then _("Receive 10 feathers and skip 3 turns, including this one.")
      when 'curiosity' then _("Ask everyone a quiz question. Each correct answer earns 4 feathers.")
      when 'tiny_recoil' then _("Receive 2 feathers and move back 2 squares.")
      when 'good_draw' then _("Draw 3 cards.")
      when 'oil_stain' then _("Leave it on your square. Take 2 feathers from the next other duck to land there and move them back 1 square. Your own duck leaves the card in place.")
      when 'die_normalizing' then _("Restore the ordinary six-sided die for yourself or another duck.")
      when 'altruism' then _("Receive 4 feathers and leave the card on your square. The next duck to land there moves forward 3 squares.")
      when 'thick_die' then _("Leave it on your square. The next duck to land there uses a three-sided die for their next 2 race rolls.")
      when 'golden_sleep' then _("An opponent skips 2 turns and receives 6 feathers from the game.")
      else raise ArgumentError, 'Unknown race card'
      end
      cost = n_("Cost: %{count} feather.", "Cost: %{count} feathers.", card.cost) % {count: card.cost} if card.cost.positive?
      [card_name(type) + '.', description, cost].compact.join(' ')
    end

    def surface_spec(replay, viewer)
      return info_surface(result_text(replay)) if replay.finished?
      return info_surface("") unless replay.state[:race]
      if replay.state[:round]
        return challenge_surface_spec(replay, viewer)
      end
      race, seat = replay.state[:race], player_index(replay.players, viewer)
      return info_surface(standings_text(replay)) unless seat
      racer = race[:racers].fetch(seat)
      actions = legal_actions(replay, viewer)
      cards = racer[:hand].each_with_index.map do |copy, index|
        plays = actions.select { |action| action.dig("input", "kind") == "play" && action.dig("input", "card") == copy.id }
        choices = if Logic::Cards::BY_ID.fetch(copy.type).target == :opponent && plays.length == 1
          []
        elsif [:opponent, :any].include?(Logic::Cards::BY_ID.fetch(copy.type).target)
          plays.map { |action| GameSurfaces::CardChoice.new(id: action["input"]["target"],
            label: participant_name(replay.players.fetch(action["input"]["target"])), value: card_action_value(action)) }
        else []
        end
        default = plays.first || {"input" => {"kind" => "play", "card" => copy.id}}
        GameSurfaces::Card.new(id: copy.id, label: card_name(copy.type), value: card_action_value(default),
          choices: choices, choice_header: _("Choose a player"),
          sort_keys: {"none" => [index], "number" => [Logic::Cards::POOL.index(copy.type), copy.id]})
      end
      # Keep the command in place between turns. Like the cards above it,
      # an attempted action is still validated against the current replay.
      commands = [GameSurfaces::Command.new(id: "roll", label: _("Roll the die"), enabled: true)]
      hand = GameSurfaces::CardTableSpec.new(default_sort: default_hand_sort, sort_modes: hand_sort_modes, zones: [GameSurfaces::CardZoneSpec.new(id: "hand", header: _("Your cards"),
        cards: cards, empty_label: _("Your hand is empty"), hand_order: racer[:hand].map(&:id),
        hand_epoch: [replay.state[:session_id], seat, racer[:hand_epoch]].join(":"), commands: commands, select_drawn: false)])
      parts = [GameSurfaces::SurfacePart.new(id: "hand", surface: hand)]
      GameSurfaces::CompositeSpec.new(parts: parts)
    end

    def custom_game_shortcuts(replay, viewer)
      return [] unless replay.state[:race]
      if (round = replay.state[:round]) && Logic::ChallengeEngine::REALTIME.include?(round[:challenge][:kind])
        # The native point adapter supplies its own controls, never the race
        # Space binding that would conflict with a serve or a ball defence.
        return realtime_shortcuts(replay, viewer)
      end
      seat = player_index(replay.players, viewer)
      keys = [announcement_shortcut(key: "t", label: _("read the turn or challenge"), message: turn_text(replay)),
        announcement_shortcut(key: "s", label: _("read the race standings"), message: standings_text(replay)),
        browse_shortcut(key: "v", label: _("browse the track"), prompt: _("Peaceful Pond"),
          default_value: seat && Logic::Board.square(replay.state[:race][:racers].fetch(seat)[:progress]),
          choices: (1..30).map { |square| ShortcutChoice.new(value: square, label: square_text(replay, square)) })]
      keys << announcement_shortcut(key: "c", label: _("read your position and feathers"),
        message: racer_text(replay, seat)) if seat
      if round && (view = local_client&.local_view).is_a?(Hash) && view[:type] == round[:challenge][:kind]
        keys << announcement_shortcut(key: "p", label: _("repeat the task"),
          message: Logic::ChallengePresentation.reminder(view[:type], view))
      end
      return keys if round
      if legal_actions(replay, viewer).any? { |action| action.dig("input", "kind") == "roll" }
        keys << GameShortcut.new(key: "space", label: _("roll the die"), kind: :action,
          action_kind: "command", action_name: "roll")
      end
      if seat
        descriptions = replay.state[:race][:racers].fetch(seat)[:hand].to_h do |copy|
          [copy.id, {"kind" => "duck", "action" => "describe", "card_id" => copy.id}]
        end
        keys << surface_shortcut(key: "d", label: _("describe the selected card"), command: "selected_card_action",
          payload: {"hand_id" => "hand", "actions" => descriptions, "shortcut" => "d"})
      end
      keys
    end

    def history_entries_for_display(replay, viewer, surface_state: {})
      replay.history.reject { |entry| entry.kind == :scenery && !same_user?(entry.actor, viewer) }
    end

    def describe_event(event, repository, replay, viewer)
      event_id = repository.event_id(event).to_i
      history_entries_for_display(replay, viewer).filter_map do |entry|
        next unless entry.event_id.to_i == event_id
        # Keep the race boundary in history without an extra startup message.
        next if [:start, :started, :turn, :result].include?(entry.kind)
        entry.text unless entry.text.to_s.empty?
      end
    end

    def paced_event_presentation?; true; end

    # Split only presentation, never the accepted action or its random draw.
    # The shared queue blocks moves (not chat/navigation) until the last stage.
    def event_presentation_stages(event, repository, before, after, viewer)
      event_id = repository.event_id(event).to_i
      history = after.history.select { |entry| entry.event_id.to_i == event_id }
      shown = history_entries_for_display(after, viewer)
      observation = challenge_observation_result(before, after, viewer) if history.any? { |entry| entry.kind == :challenge_result }
      stage = lambda do |entries, delay, defer = false|
        descriptions = entries.flat_map do |entry|
          next [] unless shown.include?(entry) && ![:start, :started, :turn, :result].include?(entry.kind) && !entry.text.to_s.empty?
          entry.kind == :challenge_result ? Array(observation) + [entry.text] : [entry.text]
        end
        {history: entries, descriptions: descriptions, delay: delay, defer_replay: defer}
      end
      changed_turn = before&.state&.dig(:race, :turn_number) && !after.finished? &&
        before.state.dig(:race, :turn_number) != after.state.dig(:race, :turn_number)
      challenge = after.state.dig(:round, :challenge)
      # Speed challenges prepare before their opening countdown. Count ducks
      # counts down only after the ducks, so it still needs the introduction.
      opening_countdown = challenge && challenge[:kind] != 'count_ducks' &&
        (challenge[:kind] == 'sound_order' || GameRoomDuckRacing::ChallengeEngine::SPEED_TYPES.include?(challenge[:kind]))
      challenge_delay = history.any? { |entry| [:challenge, :quiz_question].include?(entry.kind) } && challenge &&
        !opening_countdown ? 2.0 : 0.0
      challenge_delay = 3.0 if challenge_delay > 0 && challenge[:kind] == 'count_ducks'
      ending_delay = [changed_turn ? 2.0 : 0.0, challenge_delay].max
      stages = if (index = history.index { |entry| entry.kind == :rolled })
        [stage.call(history.take(index + 1), 1.0, true),
          stage.call(history.drop(index + 1), ending_delay)]
      elsif (index = history.index { |entry| entry.kind == :challenge_result })
        last_result = index
        last_result += 1 while history[last_result + 1]&.kind == :frozen
        result = after.state.fetch(:last_resolution).fetch(:settlement)
        feathers = settlement_feathers_text(result, after.players)
        if result.winner && (!feathers.empty? || last_result > index)
          winner_stage = stage.call(history.take(index + 1), 2.0, true)
          winner_stage[:descriptions] = stage.call(history.take(index), 0.0)[:descriptions] +
            Array(observation) + [settlement_outcome_text(result, after.players)]
          feathers_stage = stage.call(history[(index + 1)..last_result], 2.0, true)
          feathers_stage[:descriptions].unshift(feathers) unless feathers.empty?
          [winner_stage, feathers_stage, stage.call(history.drop(last_result + 1), challenge_delay)]
        else
          [stage.call(history.take(last_result + 1), 2.0, true), stage.call(history.drop(last_result + 1), challenge_delay)]
        end
      else
        [stage.call(history, ending_delay)]
      end

      # Card and square effects can chain several moves in one accepted action.
      # Keep each destination with its rewards; pause only after its preceding
      # displacement announcement, including a resumed challenge continuation.
      stages = split_movement_stages(stages, stage)

      memory = before&.state&.dig(:round)
      if memory && memory[:phase] == :playing && memory[:challenge][:kind] == 'sound_memory'
        # These choices must be heard, but must not become searchable history.
        # Wait for the client's digit/sound/result sequence before the normal
        # totals, winner, feather settlement or next-player announcement.
        feedback = stage.call([], 0.0, true).merge(wait_for_client: true, wait_for_sounds: true)
        stages.unshift(feedback)
        current = after.state[:round]
        if current && current[:phase] == :playing && current[:challenge][:id] == memory[:challenge][:id]
          next_turn = Logic::ChallengeEngine.current_turn(current[:engine])
          previous_start = memory[:engine].dig(:model, :public, :turn_started_ms)
          next_start = current[:engine].dig(:model, :public, :turn_started_ms)
          if next_turn && next_start != previous_start
            stages.last[:descriptions] << (_("%{player}'s turn.") % {player: participant_name(after.players.fetch(next_turn))})
          end
        end
      end
      stages
    end

    def turn_announcement(replay, viewer)
      super unless skipped_race_turn?(replay)
    end

    def turn_transition_history_entry(before_replay, after_replay, event_id:)
      super unless skipped_race_turn?(after_replay)
    end

    def playable_card_navigation(replay, viewer)
      return if replay.state[:round]
      cards = legal_actions(replay, viewer).select { |action| action.dig("input", "kind") == "play" }
        .group_by { |action| action["input"]["card"] }
      return if cards.empty?
      card_navigation_spec(hand_id: "hand", card_actions: cards,
        automatic_card_ids: cards.select { |_id, actions| actions.length == 1 }.keys)
    end

    def racer_text(replay, seat)
      racer, race = replay.state[:race][:racers].fetch(seat), replay.state[:race]
      square = Logic::Board.square(racer[:progress])
      parts = [_('%{player}: lap %{lap} of %{laps}, square %{square} (%{name}), feathers: %{feathers}, cards: %{cards}.') % {
        player: participant_name(replay.players.fetch(seat)), lap: [racer[:progress] / 30 + 1, race[:laps]].min,
        laps: race[:laps], square: square, name: square_name(square), feathers: racer[:feathers], cards: racer[:hand].length}]
      parts << n_("Frozen for %{count} more turn.", "Frozen for %{count} more turns.", racer[:frozen_turns]) % {count: racer[:frozen_turns]} if racer[:frozen_turns].positive?
      parts << n_("Skipping %{count} more turn.", "Skipping %{count} more turns.", racer[:skip_turns]) % {count: racer[:skip_turns]} if racer[:skip_turns].positive?
      parts << n_("Die: 1 to %{sides}, %{count} race roll left.", "Die: 1 to %{sides}, %{count} race rolls left.", racer[:die_rolls]) % {sides: racer[:die_sides], count: racer[:die_rolls]} if racer[:die_rolls].positive?
      parts.join(" ")
    end

    def standings_text(replay)
      race = replay.state[:race]
      return _("Preparing the race.") unless race
      race[:racers].keys.sort_by { |seat| [-race[:racers][seat][:progress], seat] }
        .map { |seat| racer_text(replay, seat) }.join("\n")
    end

    def turn_text(replay)
      return result_text(replay) if replay.finished?
      round, race = replay.state.values_at(:round, :race)
      return _("Preparing the race.") unless race
      if round && round[:phase] == :playing && Logic::ChallengeEngine::SEQUENTIAL.include?(round[:challenge][:kind])
        engine = round[:engine]
        if engine && !Logic::ChallengeEngine.finished?(engine)
          seat = Logic::ChallengeEngine.current_turn(engine)
          return _("%{player}'s turn.") % {player: participant_name(replay.players.fetch(seat))} unless seat.nil?
        end
      end
      return _("%{challenge}: %{players}.") % {challenge: challenge_name(round[:challenge][:kind]),
        players: round[:challenge][:participants].map { |seat| participant_name(replay.players.fetch(seat)) }.join(", ")} if round
      if skipped_race_turn?(replay)
        return skipped_turn_text(participant_name(replay.players.fetch(race[:turn])),
          race[:racers].fetch(race[:turn])[:frozen_turns].positive?)
      end
      _("%{player}'s turn.") % {player: participant_name(replay.players.fetch(race[:turn]))}
    end

    def square_text(replay, square)
      race = replay.state[:race]
      effects = Logic::Board::SQUARES.fetch(square).map { |effect| effect_text(effect) }
      effects << _("No special effect.") if effects.empty?
      present = race[:racers].filter_map { |seat, racer| participant_name(replay.players.fetch(seat)) if Logic::Board.square(racer[:progress]) == square }
      effects << _("Ducks: %{players}.") % {players: present.join(", ")} unless present.empty?
      trap = race[:traps][square]
      effects << _("Placed card: %{card}, by %{player}.") % {card: card_name(trap[:card].type),
        player: participant_name(replay.players.fetch(trap[:owner]))} if trap
      _("Square %{square}: %{name}. %{description}") % {square: square, name: square_name(square), description: effects.join(" ")}
    end

    def effect_text(effect)
      kind, value, extra = effect
      case kind
      when :move
        value.positive? ? n_("Move forward %{count} square.", "Move forward %{count} squares.", value) % {count: value} : n_("Move back %{count} square.", "Move back %{count} squares.", -value) % {count: -value}
      when :random_move then _("Move forward or back by a random distance from %{first} to %{last} squares.") % {first: value, last: extra}
      when :feathers
        value.positive? ? n_("Receive %{count} feather.", "Receive %{count} feathers.", value) % {count: value} : n_("Lose %{count} feather.", "Lose %{count} feathers.", -value) % {count: -value}
      when :steal_feathers then n_("The card's owner takes %{count} feather from the affected duck.", "The card's owner takes %{count} feathers from the affected duck.", value) % {count: value}
      when :cards then n_("Draw %{count} card.", "Draw %{count} cards.", value) % {count: value}
      when :everyone_cards then n_("Everyone draws %{count} card.", "Everyone draws %{count} cards.", value) % {count: value}
      when :steal_cards then _("Take one random card from your opponent.")
      when :swap_hands then _("Exchange your whole hand with your opponent.")
      when :pass_hands then _("Everyone passes their whole hand to the next player.")
      when :skip then n_("Skip %{count} turn.", "Skip %{count} turns.", value) % {count: value}
      when :die
        extra.zero? ? _("Restore the ordinary six-sided die.") : n_("Use a die from 1 to %{sides} for %{count} race roll.", "Use a die from 1 to %{sides} for %{count} race rolls.", extra) % {sides: value, count: extra}
      when :duel then _("Play a random two-player challenge against your opponent.")
      when :group_challenge then _("All unfrozen ducks play a random challenge.")
      when :quiz then _("Everyone answers a quiz question. Each correct answer earns 4 feathers.")
      when :chance then _("A separate %{chance}%% chance: %{effect}") % {chance: value, effect: effect_text(effect.drop(2))}
      else raise ArgumentError, "Unknown public race effect"
      end
    end

    private

    def split_movement_stages(stages, stage)
      stages.flat_map do |part|
        split, offset = [], 0
        part[:history].each_with_index do |entry, index|
          next unless entry.kind == :displacement
          split << stage.call(part[:history][offset..index], 1.0, true)
          offset = index + 1
        end
        if split.empty?
          [part]
        else
          split << stage.call(part[:history].drop(offset), part[:delay], part[:defer_replay])
        end
      end
    end

    # The usual result/feather queue owns these lines too. Participants keep
    # their concise result; observers see the final numbers or revealed quiz
    # choices only after the ordinary verifier has resolved the challenge.
    def challenge_observation_result(before, after, viewer)
      challenge = before&.state&.dig(:round, :challenge)
      result = after.state[:last_resolution]
      return [] unless challenge && result && result[:id] == challenge[:id] && !result[:cancelled]
      return [] if challenge[:participants].include?(player_index(after.players, viewer))
      return [] unless %w[copy_number quiz].include?(challenge[:kind])

      lines = []
      if challenge[:kind] == 'copy_number' && !result[:answer].nil?
        lines << (_("Correct answer: %{answer}.") % {answer: result[:answer]})
      end
      choices = resources_for(after.state[:options]).fetch(:questions).draw(seed: challenge[:seed])[:choices] if challenge[:kind] == 'quiz'
      result[:results].each do |seat, answer|
        value = answer[:answer]
        detail = value.nil? ? _("No answer") : choices ? choices.fetch(value) : value.to_s
        lines << (_("%{player}: %{result}.") % {player: participant_name(after.players.fetch(seat)), result: GameRoomContent.utf8(detail)})
      end
      lines
    end

    def skipped_race_turn?(replay)
      race = replay&.state&.dig(:race)
      return false unless race && !replay.state[:round] && !replay.finished?
      racer = race[:racers].fetch(race[:turn])
      racer[:frozen_turns].positive? || racer[:skip_turns].positive?
    end

    def skipped_turn_text(player, frozen)
      template = frozen ? _("%{player} is frozen and skips this turn.") : _("%{player} skips this turn.")
      template % {player: player}
    end

    # Local flavour only: no random draws, extra server events or effects.
    def square_scenery(square)
      case square
      when 1 then _("The starting line is marked on the bank.")
      when 2 then _("Trees rustle above the water.")
      when 3 then _("The pond stretches out before you.")
      when 4 then _("Small waves lap against the left bank.")
      when 5 then _("The diving board bends over the water.")
      when 6 then _("Sunshine warms the south bank.")
      when 7, 20 then _("Ducklings quack from their nest.")
      when 8 then _("The water is cool in the shade of the trees.")
      when 9 then _("A narrow path winds through the reeds.")
      when 10, 17 then _("Ripples spread across the pond.")
      when 11, 21 then _("Wide lily leaves float on the water.")
      when 12, 15 then _("Gentle waves rock you from side to side.")
      when 13 then _("The water here is pleasantly warm.")
      when 14 then _("The soft nest looks like a good place for a nap.")
      when 16 then _("The water swirls around you.")
      when 18 then _("The bottom disappears into the dark water.")
      when 19 then _("Thick reeds shelter you from the wind.")
      when 22 then _("A breeze blows across the north bank.")
      when 23 then _("Ducklings splash in the shallows.")
      when 24 then _("Mud squelches under your feet.")
      when 25 then _("Smooth pebbles line the right bank.")
      when 26 then _("Supplies wait in baskets by the path.")
      when 27 then _("Duck footprints cover the sand.")
      when 28 then _("The trees open onto a small clearing.")
      when 29 then _("A little puddle splashes under your feet.")
      when 30 then _("Flags flutter beside the finish line.")
      end
    end

    def info_surface(message)
      label = GameRoomContent.utf8(message)
      GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(
        id: "status", header: label, cards: [], empty_label: label)])
    end

    def card_action_value(action)
      input = action.fetch("input")
      [input["card"], input["target"]].join("|")
    end

    def normalize_surface_action(raw)
      if raw["kind"] == "card" && raw["action"] == "select"
        card, target = raw["card"].to_s.split("|", -1)
        return {} unless /\Aduck-card-[1-9][0-9]*\z/.match?(card.to_s) && (target.to_s.empty? || /\A[0-7]\z/.match?(target))
        {"action" => "race", "input" => {"kind" => "play", "card" => card, "target" => target.to_s.empty? ? nil : target.to_i}}
      elsif raw["kind"] == "command" && raw["action"] == "roll"
        {"action" => "race", "input" => {"kind" => "roll"}}
      else raw
      end
    end

    def append_notices(history, notices, event_id, players)
      name = ->(seat) { participant_name(players.fetch(seat)) }
      notices.each do |kind, *args|
        text = case kind
        when :started then _("The race has started.")
        when :rolled then _("%{player} rolls %{number}.") % {player: name.call(args[0]), number: args[1]}
        when :challenge_roll, :challenge_take, :challenge_draw, :challenge_stand, :challenge_hand, :challenge_turn
          challenge_turn_notice(kind, args, name.call(args[0]))
        when :played
          next if Logic::Cards::BY_ID.fetch(args[1]).target == :square
          if args[0] == args[2]
            p_("duck_racing", "%{player} plays %{card}.") % {player: name.call(args[0]), card: card_name(args[1])}
          else
            _("%{player} plays %{card} on %{target}.") % {player: name.call(args[0]), card: card_name(args[1]), target: name.call(args[2])}
          end
        when :placed then _("%{player} leaves %{card} on square %{square} (%{name}).") % {player: name.call(args[0]), card: card_name(args[1]), square: args[2], name: square_name(args[2])}
        when :moved
          distance = args[2]
          if distance && !args[1].finished
            direction = distance.positive? ?
              n_("%{player} moves forward %{count} square.", "%{player} moves forward %{count} squares.", distance) :
              n_("%{player} moves back %{count} square.", "%{player} moves back %{count} squares.", -distance)
            history << HistoryEntry.new(event_id: event_id, actor: "", kind: :displacement,
              text: GameRoomContent.utf8(direction % {player: name.call(args[0]), count: distance.abs}))
          end
          movement_notice(history, args[0], args[1], name.call(args[0]), final_lap: args[3])
        when :final_lap then _("%{player} begins the final lap.") % {player: name.call(args[0])}
        when :stayed then _("%{player} remains at the start.") % {player: name.call(args[0])}
        when :feathers
          args[1].positive? ? n_("%{player} receives %{count} feather.", "%{player} receives %{count} feathers.", args[1]) % {player: name.call(args[0]), count: args[1]} :
            n_("%{player} loses %{count} feather.", "%{player} loses %{count} feathers.", -args[1]) % {player: name.call(args[0]), count: -args[1]}
        when :drew_cards then n_("%{player} draws %{count} card.", "%{player} draws %{count} cards.", args[1]) % {player: name.call(args[0]), count: args[1]}
        when :stole_feathers then n_("%{player} takes %{count} feather from %{other}.", "%{player} takes %{count} feathers from %{other}.", args[2]) % {player: name.call(args[0]), other: name.call(args[1]), count: args[2]}
        when :stole_card then _("%{player} takes a card from %{other}.") % {player: name.call(args[0]), other: name.call(args[1])}
        when :swapped_hands then _("%{player} exchanges hands with %{other}.") % {player: name.call(args[0]), other: name.call(args[1])}
        when :passed_hands then _("Everyone passes their hand to the next player.")
        when :skip_added then n_("%{player} will skip %{count} turn.", "%{player} will skip %{count} turns.", args[1]) % {player: name.call(args[0]), count: args[1]}
        when :skipped then skipped_turn_text(name.call(args[0]), args[1])
        when :thawed then n_("%{player} thaws and receives %{count} feather.", "%{player} thaws and receives %{count} feathers.", args[1]) % {player: name.call(args[0]), count: args[1]}
        when :frozen then n_("%{player} is frozen for %{count} turn.", "%{player} is frozen for %{count} turns.", args[1]) % {player: name.call(args[0]), count: args[1]}
        when :die_changed
          if args[2].zero?
            _("%{player} returns to the ordinary six-sided die.") % {player: name.call(args[0])}
          else
            n_("%{player} will roll from 1 to %{sides} for the next %{count} race roll.",
              "%{player} will roll from 1 to %{sides} for the next %{count} race rolls.", args[2]) % {
                player: name.call(args[0]), sides: args[1], count: args[2]}
          end
        when :trap then _("%{player} lands on %{card}, left by %{other}.") % {player: name.call(args[0]), card: card_name(args[1]), other: name.call(args[2])}
        when :challenge
          if args[1] == 'quiz' && [:square_question, :question_card].include?(args[4])
            kind = :quiz_question
            _("Question for everyone.")
          else
            initiator = args[3]
            others = args[2].reject { |seat| seat == initiator }.map(&name)
            announcement = if initiator.nil?
              _("Challenge for %{players}.") % {players: others.join(', ')}
            else
              _("%{player} starts a challenge with %{others}.") % {player: name.call(initiator), others: others.join(', ')}
            end
            announcement + "\n" + challenge_name(args[1]) + '.'
          end
        when :challenge_details then challenge_details_text(args[0], args[1], args[2], players)
        when :challenge_result then settlement_text(args[1], players)
        when :challenge_cancelled then _("Challenge cancelled. Feathers unchanged.")
        end
        next if text.to_s.empty?
        entry = HistoryEntry.new(event_id: event_id, text: GameRoomContent.utf8(text), actor: "", kind: kind)
        entry.field, entry.value = args[0], args[1].lap if kind == :moved
        entry.value = args[1] if kind == :skipped # Whether this turn was skipped because of freezing.
        entry.value = args[1] if kind == :trap
        history << entry
        if kind == :moved && !args[1].finished
          history << HistoryEntry.new(event_id: event_id, kind: :scenery,
            actor: players.fetch(args[0]), text: square_scenery(args[1].square))
        end
      end
    end

    def challenge_turn_notice(kind, args, player)
      case kind
      when :challenge_roll
        numbers = args[1].length == 2 ? _("%{first} and %{second}") % {first: args[1][0], second: args[1][1]} : args[1].first.to_s
        template = args[1].length == 1 ? _("%{player} rolls %{number}.") : _("%{player} rolls %{number}. Total: %{total}.")
        template % {player: player, number: numbers, total: args[2]}
      when :challenge_take
        values = args[1].map(&:to_s)
        balls = values.length == 1 ? values.first : _("%{first} and %{second}") % {first: values[0...-1].join(', '), second: values.last}
        _("%{player} takes %{balls}.") % {player: player, balls: balls}
      when :challenge_draw
        draw = _("%{player} draws %{card}. Total: %{total}.") % {
          player: player, card: Logic::ChallengePresentation.card_rank(args[1]), total: args[2]}
        draw += "\n" + (_("%{player} goes over 21.") % {player: player}) if args[2] > 21
        draw
      when :challenge_stand
        _("%{player} stops at %{total}.") % {player: player, total: args[1]}
      when :challenge_hand
        _("%{player} receives %{cards}. Total: %{total}.") % {
          player: player, cards: args[1].map { |rank| Logic::ChallengePresentation.card_rank(rank) }.join(", "), total: args[2]}
      when :challenge_turn then _("%{player}'s turn.") % {player: player}
      end
    end

    def movement_notice(history, seat, movement, player, final_lap: false)
      return _("%{player} reaches the finish.") % {player: player} if movement.finished

      # Compare stable places, not translated text or names that can change
      # after a replacement. Stop at this place's last move, including one
      # already appended for another effect of the same action.
      previous = history.reverse_each.find do |entry|
        entry.kind == :started || (entry.kind == :moved && entry.field == seat)
      end
      previous_lap = previous&.kind == :moved ? previous.value : 1
      landing = _("%{player} lands on square %{square}. %{name}.") % {
        player: player, square: movement.square, name: square_name(movement.square)}
      text = landing
      if movement.lap != previous_lap && !final_lap
        transition = movement.lap > previous_lap ? _("Begins lap %{lap}.") : _("Returns to lap %{lap}.")
        text += " " + (transition % {lap: movement.lap})
      end
      text
    end

    def challenge_details_text(kind, results, answer, players)
      return '' if %w[copy_number dice_duel blackjack risky_dice sound_order audio_ball axel_pong].include?(kind)

      parts = []
      parts << _("Correct answer: %{answer}.") % {answer: GameRoomContent.utf8(answer.to_s)} unless answer.nil?
      return parts.join("\n") if kind == 'quiz' || Logic::ChallengeEngine::FIRST_ANSWER.include?(kind)

      results.each do |seat, result|
        player = participant_name(players.fetch(seat))
        detail = case kind
        when "rock_paper_scissors"
          {"rock" => _("Rock"), "paper" => _("Paper"), "scissors" => _("Scissors")}.fetch(result[:choice], _("No answer"))
        when "guess_number"
          result[:best] ? result[:best][:value].to_s : _("No answer")
        when "rhythm", "hit_duck"
          _("%{accuracy}%% accuracy") % {accuracy: result[:score].to_f.round(1)}
        when "simon" then n_("%{count} sound", "%{count} sounds", result[:score]) % {count: result[:score]}
        when "sound_memory" then n_("%{count} pair", "%{count} pairs", result[:score]) % {count: result[:score]}
        else result[:score].to_s
        end
        parts << _("%{player}: %{result}.") % {player: player, result: detail} unless detail.nil?
      end
      parts.join("\n")
    end

    def settlement_text(result, players)
      [settlement_outcome_text(result, players), settlement_feathers_text(result, players)]
        .reject(&:empty?).join("\n")
    end

    def settlement_outcome_text(result, players)
      lines = []
      lines << _("%{player} wins.") % {player: participant_name(players.fetch(result.winner))} if result.winner
      lines << _("The challenge ends in a draw.") if result.outcome == :draw
      lines << _("No one wins the challenge.") if result.outcome == :no_winner
      lines << _("No one answered correctly.") if result.outcome == :quiz && result.grants.empty?
      lines.join("\n")
    end

    def settlement_feathers_text(result, players)
      lines = []
      result.transfers.each do |transfer|
        lines << n_("%{player} takes %{count} feather from %{other}.", "%{player} takes %{count} feathers from %{other}.", transfer.amount) % {player: participant_name(players.fetch(transfer.to)),
          other: participant_name(players.fetch(transfer.from)), count: transfer.amount}
      end
      result.burned.each { |seat, count| lines << n_("%{player} loses %{count} penalty feather.", "%{player} loses %{count} penalty feathers.", count) % {player: participant_name(players.fetch(seat)), count: count} }
      result.grants.group_by { |_seat, count| count }.each do |count, grants|
        names = grants.map { |seat, _count| participant_name(players.fetch(seat)) }
        if names.size == 1
          lines << n_("%{player} receives %{count} feather.", "%{player} receives %{count} feathers.", count) % {player: names.first, count: count}
        else
          lines << n_("%{players} each receive %{count} feather.", "%{players} each receive %{count} feathers.", count) % {players: names.join(', '), count: count}
        end
      end
      lines.join("\n")
    end
  end
end
