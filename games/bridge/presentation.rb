require_relative "../../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  # Accessible presentation of Bridge: hands grouped by suit, spoken calls,
  # the dummy as a second card zone and announcement shortcuts.
  class Bridge < CardGame
    DISPLAY_SUITS = %w[S H D C].freeze

    def hand_sorting_available?(replay, viewer)
      seat = seat_of(replay.state, viewer)
      seat != nil && !replay.state[:hands][seat].empty?
    end

    def surface_spec(replay, viewer)
      state = replay.state
      zones = card_zones(state, viewer)
      # A spectator sees no hand until dummy is exposed.
      if zones.empty?
        return GameSurfaces::QuestionSpec.new(id: "table", prompt: GameRoomContent.utf8(name), mode: :information,
          value: GameRoomContent.utf8(spectator_text(state)))
      end
      cards = GameSurfaces::CardTableSpec.new(zones: zones)
      question = call_question(state, viewer)
      return cards if question == nil

      GameSurfaces::CompositeSpec.new(parts: [
        GameSurfaces::SurfacePart.new(id: "auction", surface: question),
        GameSurfaces::SurfacePart.new(id: "cards", surface: cards)
      ])
    end

    def turn_announcement(replay, viewer)
      state = replay.state
      return nil if state == nil || finished_state?(state) || state[:current_player] == nil

      seat = state[:seat_to_play]
      mine = same_user?(state[:current_player], viewer)
      if state[:phase] == :bidding
        return _("You are bidding.") if mine

        return _("%{player} (%{seat}) is bidding.") % { player: participant_name(state[:current_player]), seat: seat_name(seat) }
      end
      if seat == dummy_seat(state)
        return _("Play a card from dummy.") if mine

        return _("%{player} plays from dummy (%{seat}).") % { player: participant_name(state[:current_player]), seat: seat_name(seat) }
      end
      return _("It is your turn.") if mine

      _("It is %{player}'s turn (%{seat}).") % { player: participant_name(state[:current_player]), seat: seat_name(seat) }
    end

    def turn_transition_history_entry(before_replay, after_replay, event_id:)
      return nil if after_replay == nil || after_replay.finished? || after_replay.current_player == nil

      after = after_replay.state
      before = before_replay&.state
      if before != nil && before[:phase] == after[:phase] && before[:seat_to_play] == after[:seat_to_play] &&
          before[:round] == after[:round]
        return nil
      end

      player = after[:current_player]
      seat = after[:seat_to_play]
      text = if after[:phase] == :bidding
        _("%{player} (%{seat}) is bidding.") % { player: participant_name(player), seat: seat_name(seat) }
      elsif seat == dummy_seat(after)
        _("%{player} plays from dummy (%{seat}).") % { player: participant_name(player), seat: seat_name(seat) }
      else
        _("It is %{player}'s turn (%{seat}).") % { player: participant_name(player), seat: seat_name(seat) }
      end
      HistoryEntry.new(key: "turn:#{event_id.to_i}:#{after[:phase]}:#{seat}", text: text, event_id: event_id.to_i,
        actor: player, kind: :turn)
    end

    # Declarer decides for two seats, so a new decision includes the seat.
    def required_decision_key(replay, viewer)
      key = super
      key == nil ? nil : key + [replay.state[:round], replay.state[:seat_to_play]]
    end

    def bot_observation(replay, actor)
      state = replay.state
      seat = seat_of(state, actor)
      contract = state[:contract]
      dummy = dummy_seat(state)
      {
        "seat" => seat,
        "phase" => state[:phase].to_s,
        "dealer" => state[:dealer],
        "vulnerability" => state[:vulnerability].to_s,
        "hand" => seat == nil ? [] : state[:hands][seat].dup,
        "dummy" => state[:dummy_visible] && dummy != nil ? state[:hands][dummy].dup : nil,
        "calls" => state[:calls].map(&:dup),
        "contract" => contract == nil ? nil : contract.to_h.transform_keys(&:to_s),
        "seat_to_play" => state[:seat_to_play],
        "trick" => state[:trick].map(&:dup),
        "played" => state[:completed_tricks].flat_map { |trick| trick[:cards].map(&:dup) },
        "tricks_won" => state[:tricks_won].dup,
        "scores" => state[:scores].dup
      }
    end

    def shortcut_features
      [:bidding] + super + [:hand, :table_cards, :table_cards_list, :led_suit, :round_summary, :round_information, :scores]
    end

    def game_shortcuts(replay, viewer)
      super
    end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      return nil if state == nil

      case feature.to_sym
      when :bidding
        calls = same_user?(state[:current_player], viewer) ? legal_calls(state) : []
        return { message: auction_text(state) } if calls.empty?

        {
          kind: :choice,
          label: _("make a call"),
          prompt: _("Choose your call. %{auction}") % { auction: auction_text(state) },
          action_kind: "command",
          action_name: "call",
          value_key: "call",
          choices: calls.map { |call| ShortcutChoice.new(value: call, label: call_label(call)) }
        }
      when :hand then { message: own_hand_text(state, viewer) }
      when :table_cards then { message: trick_cards_text(state) }
      when :table_cards_list then trick_browse_data(state)
      when :led_suit then { message: led_suit_text(state) }
      when :round_summary then { message: deal_summary_text(state) }
      when :round_information then { message: personal_text(state, viewer) }
      when :scores then { message: scores_text(state) }
      else super
      end
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      return [] if state == nil

      [
        announcement_shortcut(key: "d", label: _("read dummy's hand"), message: dummy_hand_text(state, viewer)),
        announcement_shortcut(key: "k", label: _("read the contract"), message: contract_status_text(state)),
        announcement_shortcut(key: "l", label: _("read the auction"), message: auction_text(state)),
        browse_shortcut(key: "l", modifiers: [:control], label: _("browse the auction"), prompt: _("Auction"),
          choices: auction_choices(state)),
        announcement_shortcut(key: "p", label: _("read the previous trick"), message: previous_trick_text(state))
      ]
    end

    private

    def seat_name(seat)
      case seat
      when 0 then _("North")
      when 1 then _("East")
      when 2 then _("South")
      when 3 then _("West")
      else ""
      end
    end

    def seated_name(state, seat)
      _("%{seat} (%{player})") % { seat: seat_name(seat), player: participant_name(state[:seats][seat]) }
    end

    def side_name(side)
      side == 0 ? _("North-South") : _("East-West")
    end

    def side_label(state, side)
      members = [side, side + 2].map { |seat| participant_name(state[:seats][seat]) }
      _("%{side} (%{players})") % { side: side_name(side), players: members.join(_(" and ")) }
    end

    def card_rank(card)
      R.card_rank(card)
    end

    def card_suit(card)
      R.card_suit(card)
    end

    def card_label(card)
      playing_card_label(card)
    end

    def suit_name(suit)
      { "C" => _("clubs"), "D" => _("diamonds"), "H" => _("hearts"), "S" => _("spades") }.fetch(suit, suit)
    end

    def rank_name(rank)
      { "T" => "10", "J" => _("jack"), "Q" => _("queen"), "K" => _("king"), "A" => _("ace") }.fetch(rank, rank)
    end

    def call_label(call)
      case call
      when R::PASS then _("pass")
      when R::DOUBLE then _("double")
      when R::REDOUBLE then _("redouble")
      else strain_bid_label(R.bid_level(call), R.bid_strain(call))
      end
    end

    def strain_bid_label(level, strain)
      case strain
      when "C" then n_("%{level} club", "%{level} clubs", level) % { level: level }
      when "D" then n_("%{level} diamond", "%{level} diamonds", level) % { level: level }
      when "H" then n_("%{level} heart", "%{level} hearts", level) % { level: level }
      when "S" then n_("%{level} spade", "%{level} spades", level) % { level: level }
      else _("%{level} no trump") % { level: level }
      end
    end

    def contract_label(contract)
      text = strain_bid_label(contract.level, contract.strain)
      text = _("%{contract} doubled") % { contract: text } if contract.doubled == 1
      text = _("%{contract} redoubled") % { contract: text } if contract.doubled == 2
      text
    end

    def vulnerability_text(vulnerability)
      case vulnerability.to_sym
      when :ns then _("North-South vulnerable")
      when :ew then _("East-West vulnerable")
      when :both then _("both sides vulnerable")
      else _("neither side vulnerable")
      end
    end

    # Bridge players read a hand suit by suit, highest card first.
    def hand_by_suits(cards)
      DISPLAY_SUITS.map do |suit|
        ranks = cards.select { |card| card_suit(card) == suit }.sort_by { |card| -R.rank_index(card) }
        values = ranks.empty? ? _("none") : ranks.map { |card| rank_name(card_rank(card)) }.join(", ")
        _("%{suit}: %{cards}") % { suit: suit_name(suit), cards: values }
      end.join("; ")
    end

    def card_sort_key(card)
      [DISPLAY_SUITS.index(card_suit(card)), -R.rank_index(card)]
    end

    def card_zones(state, viewer)
      seat = seat_of(state, viewer)
      zones = []
      if seat != nil
        hand = state[:hands][seat]
        zones << hand_zone("hand", own_hand_header(state, seat), hand, [viewer, state[:round]].join(":"))
      end
      dummy = dummy_seat(state)
      if state[:dummy_visible] && dummy != nil && dummy != seat
        header = _("Dummy, %{seat}, %{count} cards") % { seat: seated_name(state, dummy), count: state[:hands][dummy].length }
        zones << hand_zone("dummy", header, state[:hands][dummy], ["dummy", dummy, state[:round]].join(":"))
      end
      zones
    end

    def hand_zone(id, header, hand, epoch)
      cards = hand.sort_by { |card| card_sort_key(card) }.map do |card|
        GameSurfaces::Card.new(id: card, label: card_label(card), value: card,
          sort_keys: standard_hand_sort_keys(rank: card_rank(card), suit: card_suit(card), position: hand.index(card)))
      end
      GameSurfaces::CardZoneSpec.new(id: id, header: GameRoomContent.utf8(header), cards: cards, hand_order: hand.dup,
        hand_epoch: epoch, empty_label: _("No cards"))
    end

    def own_hand_header(state, seat)
      if state[:phase] == :playing && seat == dummy_seat(state)
        return _("Your hand, %{seat}: you are dummy and your partner plays these cards") % { seat: seat_name(seat) }
      end

      _("Your hand, %{seat}, %{points} high card points") % { seat: seat_name(seat), points: R.high_card_points(state[:initial_hands][seat]) }
    end

    def call_question(state, viewer)
      return nil if state[:phase] != :bidding || !same_user?(state[:current_player], viewer)

      options = legal_calls(state).map do |call|
        GameSurfaces::QuestionOption.new(id: call, label: GameRoomContent.utf8(call_label(call)), value: call)
      end
      GameSurfaces::QuestionSpec.new(id: "call", prompt: GameRoomContent.utf8(call_prompt(state)), mode: :single_choice,
        options: options, value: R::PASS, required: true, submit_on_select: true)
    end

    def call_prompt(state)
      last = R.last_bid(state[:calls])
      return _("Your call. No bid has been made yet.") if last == nil

      _("Your call. The last bid is %{call} by %{seat}.") % { call: call_label(last[1]), seat: seat_name(last[0]) }
    end

    # History ------------------------------------------------------------------

    def starting_history_for(state)
      seats = state[:seats].each_with_index.map { |_player, seat| seated_name(state, seat) }
      HistoryEntry.new(key: "start", text: _("Bridge started: %{seats}.") % { seats: seats.join(", ") }, event_id: 0,
        actor: "", kind: :start)
    end

    def deal_text(state)
      if duplicate?(state)
        return _("Board %{board} of %{boards}. Dealer: %{dealer}. %{vulnerability}.") % {
          board: state[:round], boards: state[:options]["boards"], dealer: seated_name(state, state[:dealer]),
          vulnerability: capitalize_text(vulnerability_text(state[:vulnerability]))
        }
      end

      _("Deal %{round}. Dealer: %{dealer}. %{vulnerability}.") % {
        round: state[:round], dealer: seated_name(state, state[:dealer]),
        vulnerability: capitalize_text(vulnerability_text(state[:vulnerability]))
      }
    end

    def capitalize_text(text)
      text = GameRoomContent.utf8(text)
      text.empty? ? text : text[0].upcase + text[1..]
    end

    def call_history_text(state, seat, call)
      _("%{seat}: %{call}.") % { seat: seated_name(state, seat), call: call_label(call) }
    end

    def contract_announcement(state, contract, leader)
      _("Contract: %{contract}, declarer %{declarer}. %{leader} makes the opening lead.") % {
        contract: contract_label(contract), declarer: seated_name(state, contract.declarer), leader: seated_name(state, leader)
      }
    end

    def play_text(state, seat, card)
      if seat == dummy_seat(state)
        return _("Dummy, %{seat}: %{card}.") % { seat: seat_name(seat), card: card_label(card) }
      end

      _("%{seat}: %{card}.") % { seat: seated_name(state, seat), card: card_label(card) }
    end

    def dummy_text(state)
      dummy = dummy_seat(state)
      _("Dummy is on the table, %{seat}: %{cards}.") % { seat: seated_name(state, dummy), cards: hand_by_suits(state[:hands][dummy]) }
    end

    def trick_text(state, winner)
      _("%{seat} won the trick. Tricks: %{tricks}.") % { seat: seated_name(state, winner), tricks: tricks_count_text(state) }
    end

    def tricks_count_text(state)
      _("North-South %{ns}, East-West %{ew}") % { ns: state[:tricks_won][0], ew: state[:tricks_won][1] }
    end

    def contract_result_text(contract, tricks)
      return _("made exactly") if tricks == contract.tricks_needed
      if tricks > contract.tricks_needed
        extra = tricks - contract.tricks_needed
        return n_("made with %{count} overtrick", "made with %{count} overtricks", extra) % { count: extra }
      end

      down = contract.tricks_needed - tricks
      n_("down %{count} trick", "down %{count} tricks", down) % { count: down }
    end

    def deal_result_text(state, deal)
      contract = deal[:contract]
      outcome = _("%{contract} by %{declarer} %{result}") % {
        contract: contract_label(contract), declarer: seat_name(contract.declarer),
        result: contract_result_text(contract, deal[:tricks])
      }
      return "#{outcome}. #{duplicate_board_text(state, deal)}" if duplicate?(state)

      "#{outcome}. #{rubber_entries_text(deal[:entries])} #{_('Total: %{scores}.') % { scores: score_pairs_text(state) }}"
    end

    def duplicate_board_text(state, deal)
      score = deal[:ns_score]
      result = score == 0 ? _("no score") : _("%{points} for %{side}") % { points: score.abs, side: side_name(score > 0 ? 0 : 1) }
      reference = deal[:datum] == 0 ? _("an even reference") : _("a reference of %{points} for %{side}") % {
        points: deal[:datum].abs, side: side_name(deal[:datum] > 0 ? 0 : 1)
      }
      comparison = if state[:options]["scoring"] == "mp"
        _("Matchpoints: North-South %{ns}, East-West %{ew}.") % { ns: deal[:ns_points], ew: deal[:ew_points] }
      elsif deal[:ns_points] == deal[:ew_points]
        _("No IMPs change hands.")
      else
        side = deal[:ns_points] > 0 ? 0 : 1
        imps = [deal[:ns_points], deal[:ew_points]].max
        n_("%{side} gains %{count} IMP.", "%{side} gains %{count} IMPs.", imps) % { side: side_name(side), count: imps }
      end
      _("Score %{result}, compared with %{reference}. %{comparison}") % { result: result, reference: reference, comparison: comparison }
    end

    def rubber_entries_text(entries)
      entries.to_a.map do |side, _line, points, reason|
        case reason
        when :contract then _("%{side} score %{points} below the line.") % { side: side_name(side), points: points }
        when :overtricks then _("%{side} score %{points} for overtricks.") % { side: side_name(side), points: points }
        when :insult then _("%{side} score %{points} for making a doubled contract.") % { side: side_name(side), points: points }
        when :slam then _("%{side} score %{points} for the slam.") % { side: side_name(side), points: points }
        when :undertricks then _("%{side} score %{points} for undertricks.") % { side: side_name(side), points: points }
        when :honors then _("%{side} score %{points} for honours.") % { side: side_name(side), points: points }
        when :game then _("%{side} won a game.") % { side: side_name(side) }
        when :rubber then _("%{side} won the rubber and score %{points}.") % { side: side_name(side), points: points }
        end
      end.compact.join(" ")
    end

    def score_pairs_text(state)
      [0, 1].map { |side| _("%{side} %{score}") % { side: side_name(side), score: state[:scores][unit_id(side)] } }.join(", ")
    end

    def final_scores_text(state)
      return score_pairs_text(state) if !duplicate?(state) || state[:options]["scoring"] != "mp"

      percentages_text(state)
    end

    def percentages_text(state)
      boards = state[:deals].length
      return score_pairs_text(state) if boards == 0

      [0, 1].map do |side|
        percent = (state[:scores][unit_id(side)] * 100.0 / (2 * boards)).round(1)
        _("%{side} %{percent}%%") % { side: side_name(side), percent: percent }
      end.join(", ")
    end

    def final_result_text(state)
      return _("The match ended in a draw: %{scores}.") % { scores: final_scores_text(state) } if state[:draw]
      return nil if state[:winner] == nil

      _("%{winner} won the match: %{scores}.") % {
        winner: side_label(state, side_of_unit(state[:winner])), scores: final_scores_text(state)
      }
    end

    # Shortcut texts -----------------------------------------------------------

    def own_hand_text(state, viewer)
      seat = seat_of(state, viewer)
      return _("You are not playing at this table.") if seat == nil
      return _("Your hand is empty.") if state[:hands][seat].empty?

      _("Your hand, %{count} cards: %{cards}. %{points} high card points.") % {
        count: state[:hands][seat].length, cards: hand_by_suits(state[:hands][seat]), points: R.high_card_points(state[:hands][seat])
      }
    end

    def dummy_hand_text(state, viewer)
      dummy = dummy_seat(state)
      return _("Dummy is not on the table yet. It is shown after the opening lead.") if dummy == nil || !state[:dummy_visible]
      return _("You are dummy. Your partner plays your cards.") if dummy == seat_of(state, viewer) && state[:hands][dummy].any?

      _("Dummy, %{seat}: %{cards}.") % { seat: seated_name(state, dummy), cards: hand_by_suits(state[:hands][dummy]) }
    end

    def trick_cards_text(state)
      return _("There are no cards in the current trick.") if state[:trick].empty?

      _("Current trick: %{cards}.") % { cards: state[:trick].map { |seat, card| _("%{seat} %{card}") % { seat: seat_name(seat), card: card_label(card) } }.join("; ") }
    end

    def trick_browse_data(state)
      choices = state[:trick].map do |seat, card|
        ShortcutChoice.new(value: card, label: _("%{seat}: %{card}") % { seat: seated_name(state, seat), card: card_label(card) })
      end
      choices = [ShortcutChoice.new(value: nil, label: _("No cards have been played in this trick"))] if choices.empty?
      { kind: :browse, prompt: _("Cards on the table"), choices: choices }
    end

    def led_suit_text(state)
      return _("No suit has been led.") if state[:trick].empty?

      _("The led suit is %{suit}.") % { suit: suit_name(card_suit(state[:trick].first[1])) }
    end

    def previous_trick_text(state)
      trick = state[:completed_tricks].last
      return _("No trick has been completed in this deal.") if trick == nil

      cards = trick[:cards].map { |seat, card| _("%{seat} %{card}") % { seat: seat_name(seat), card: card_label(card) } }
      _("Previous trick: %{cards}. Won by %{seat}.") % { cards: cards.join("; "), seat: seat_name(trick[:winner]) }
    end

    def auction_entries(state)
      state[:calls].map { |seat, call| _("%{seat}: %{call}") % { seat: seat_name(seat), call: call_label(call) } }
    end

    def auction_text(state)
      return _("No calls have been made yet.") if state[:calls].empty?

      _("Auction: %{calls}.") % { calls: auction_entries(state).join("; ") }
    end

    def auction_choices(state)
      entries = auction_entries(state)
      entries = [_("No calls have been made yet.")] if entries.empty?
      entries.map { |label| ShortcutChoice.new(value: nil, label: label) }
    end

    def contract_status_text(state)
      contract = state[:contract]
      return _("There is no contract yet.") if contract == nil

      _("Contract: %{contract} by %{declarer}. Declarer needs %{needed} tricks and has %{won}.") % {
        contract: contract_label(contract), declarer: seated_name(state, contract.declarer),
        needed: contract.tricks_needed, won: state[:tricks_won][contract.side]
      }
    end

    def deal_summary_text(state)
      return _("No deal has been played yet.") if state[:round] == 0

      parts = [deal_text(state)]
      parts << contract_status_text(state) if state[:contract] != nil
      parts << _("Tricks: %{tricks}.") % { tricks: tricks_count_text(state) } if state[:phase] == :playing
      parts.join(" ")
    end

    def spectator_text(state)
      [_("You are watching this table."), deal_summary_text(state)].join(" ")
    end

    def personal_text(state, viewer)
      seat = seat_of(state, viewer)
      return _("You are watching this table.") if seat == nil

      partner = R.partner_of(seat)
      text = _("You sit %{seat}; your partner is %{partner}.") % { seat: seat_name(seat), partner: seated_name(state, partner) }
      contract = state[:contract]
      return text if contract == nil || state[:phase] != :playing

      role = if seat == contract.declarer
        _("You are declarer and also play dummy's cards.")
      elsif seat == dummy_seat(state)
        _("You are dummy.")
      else
        _("You are defending; your side needs %{count} tricks to defeat the contract.") % { count: 14 - contract.tricks_needed }
      end
      "#{text} #{role}"
    end

    def scores_text(state)
      if duplicate?(state)
        unit = state[:options]["scoring"] == "mp" ? percentages_text(state) : score_pairs_text(state)
        label = state[:options]["scoring"] == "mp" ? _("Matchpoints") : _("IMPs")
        return _("%{label} after %{boards} of %{total} boards: %{scores}.") % {
          label: label, boards: state[:deals].length, total: state[:options]["boards"], scores: unit
        }
      end

      rubber = state[:rubber]
      sides = [0, 1].map do |side|
        _("%{side}: %{games} games, %{below} below and %{above} above the line, %{total} in total") % {
          side: side_name(side), games: rubber[:games][side], below: rubber[:below][side],
          above: rubber[:above][side], total: state[:scores][unit_id(side)]
        }
      end
      game_line = _("Current game: North-South %{ns}, East-West %{ew}.") % { ns: rubber[:game_line][0], ew: rubber[:game_line][1] }
      "#{sides.join('; ')}. #{game_line}"
    end
  end
end
