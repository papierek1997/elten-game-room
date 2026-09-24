require_relative "game_participants"
require_relative "game_turn_clock"

module GameRoomSounds
  ASSET_NAMES = %w[
    connect
    disconnect
    chatmsg
    notice
    table_notice
    buzzer
    buzzer2
    ding
    shuffle
    card-shuffle
    draw
    draw2
    domino_refill
    domino_move_tile
    domino_take_chip
    farkle
    farkle_bank
    cht-roll-dice
    cht-bank
    cht-lost-points
    cht-cat-minus-8
    cht-cat-plus-8
    ninety3366
    1000_mariage
    hit1
    hit_ship1
    hit_ship2
    rocket_launch1
    rocket_launch2
    rocket_launch3
    rocket_miss
    interception
    lose1
    lose3
    lose_party
    play
    play2
    replay
    reverse
    reverse3
    roll
    skip
    win1
    win2
    win_party
  ].freeze

  BATTLESHIP_HITS = %w[hit_ship1 hit_ship2].freeze
  BATTLESHIP_LAUNCHES = %w[rocket_launch1 rocket_launch2 rocket_launch3].freeze
  # Balance the loud Battleship recordings before the user's volume controls.
  # Keep the audio files and playback handles intact for serial presentation.
  ASSET_VOLUME_GAINS = (BATTLESHIP_HITS + BATTLESHIP_LAUNCHES + ["rocket_miss"]).to_h { |name| [name, 0.2] }.freeze

  class MembershipTracker
    def initialize
      @members = nil
    end

    def observe(members)
      current = normalized_members(members)
      if @members == nil
        @members = current
        return []
      end

      joined = current.keys - @members.keys
      left = @members.keys - current.keys
      @members = current
      Array.new(joined.length, "connect") + Array.new(left.length, "disconnect")
    end

    private

    def normalized_members(members)
      GameRoomParticipants.humans(members).each_with_object({}) do |member, result|
        result[member.to_s.downcase] = member.to_s
      end
    end
  end

  module_function

  def play(program, name)
    return nil if name == nil || !ASSET_NAMES.include?(name.to_s)
    if program.respond_to?(:game_room_sound_enabled?, true)
      return nil if !program.send(:game_room_sound_enabled?, name.to_s)
    end

    gain = ASSET_VOLUME_GAINS.fetch(name.to_s, 1.0)
    if program.respond_to?(:game_room_sound_volume, true)
      volume = program.send(:game_room_sound_volume, name.to_s) * gain
      return nil if volume <= 0

      program.play_sound_from_asset(name.to_s, volume: volume)
    elsif gain != 1.0
      program.play_sound_from_asset(name.to_s, volume: gain)
    else
      program.play_sound_from_asset(name.to_s)
    end
  rescue Exception => error
    Log.warning("ELTEN Game Room sound #{name} failed: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def play_all(program, names)
    names.to_a.each { |name| play(program, name) }
  end

  def play_event(program, **event_data)
    play_all(program, Array(event_cue(**event_data)))
  rescue Exception => error
    Log.warning("ELTEN Game Room event sound failed: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  # One persisted event may carry several independent cues. SoundPool starts
  # them without waiting, so a move, its special effect and its result remain
  # audible even when they belong to the same atomic action.
  def event_cue(game:, event:, before_replay:, after_replay:, repository:, viewer:)
    cues = Array(action_cue(
      game: game,
      event: event,
      before_replay: before_replay,
      after_replay: after_replay,
      repository: repository,
      viewer: viewer
    ))
    if history_for_event(after_replay, event, repository).any? { |entry| entry.kind == :reshuffle }
      cues.unshift("card-shuffle")
    end
    cues.concat(Array(result_cue(game, before_replay, after_replay, viewer)))
    cues = cues.compact.map(&:to_s).reject(&:empty?).uniq
    return nil if cues.empty?
    return cues.first if cues.length == 1

    cues
  end

  def action_cue(game:, event:, before_replay:, after_replay:, repository:, viewer:)
    action = event["action"].to_s
    case game.id.to_s
    when "battleship"
      kinds = history_for_event(after_replay, event, repository).map(&:kind)
      cues = []
      cues << "play" if kinds.include?(:seal)
      cues << random_variant(BATTLESHIP_LAUNCHES) if kinds.include?(:shoot)
      cues << "rocket_miss" if kinds.include?(:miss)
      cues << random_variant(BATTLESHIP_HITS) if (kinds & [:hit, :sunk]).any?
      cues
    when "mancala"
      kinds = history_for_event(after_replay, event, repository).map(&:kind)
      { sow: "domino_move_tile", capture: "hit1" }.select { |kind, _| kinds.include?(kind) }.values
    when "biblios"
      kinds = history_for_event(after_replay, event, repository).map(&:kind)
      return "shuffle" if kinds.include?(:deal)
      return "draw" if kinds.include?(:take)
      return "play" if (kinds & [:allocate, :pay, :church, :scriptorium]).any?
    when "taboo"
      kinds = history_for_event(after_replay, event, repository).map(&:kind)
      { taboo_start: "shuffle", taboo_correct: "replay", taboo_skipped: "skip",
        taboo_buzzed: "buzzer2", taboo_timeout: "ding" }.select { |kind,_| kinds.include?(kind) }.values
    when "scrabble"
      kinds = history_for_event(after_replay, event, repository).map(&:kind)
      return "shuffle" if kinds.include?(:deal)
      return "play" if kinds.include?(:play)
      return "draw" if kinds.include?(:exchange)
    when "spades"
      return "shuffle" if action == "deal"
      return nil if action != "play"

      event["value"].to_s.end_with?("S") ? ["play", "draw2"] : "play"
    when "three_five_eight"
      entries = history_for_event(after_replay, event, repository)
      cues = []
      cues << "shuffle" if action == "deal"
      cues << "ding" if action == "choose_contract"
      cues << "draw" if %w[exchange return stop_exchange discard].include?(action)
      if action == "play"
        cues << "play"
        trump = after_replay&.state.to_h[:contract].to_s
        cues << "draw2" if %w[H S D C].include?(trump) && event["value"].to_s.end_with?(trump)
      end
      round_result = entries.find do |entry|
        entry.kind == :round_result && GameRoomParticipants.same?(entry.actor, viewer)
      end
      if round_result
        change = round_result.value.to_i
        cues << (change > 0 ? "win1" : (change < 0 ? "lose1" : "ding"))
      end
      cues
    when "tysiac"
      return "shuffle" if action == "deal"
      return nil if action != "play"

      mode, card = event["value"].to_s.split("|", 2)
      trump = after_replay&.state.to_h[:trump].to_s
      cues = ["play"]
      cues << "draw2" if !trump.empty? && card.to_s.end_with?(trump)
      if mode == "marriage" && history_for_event(after_replay, event, repository).any? { |entry| entry.kind == :play }
        cues << "1000_mariage"
      end
      cues
    when "ninety_nine"
      ninety_nine_cue(event, before_replay, after_replay, viewer)
    when "farkle"
      farkle_cue(event, before_replay, after_replay, repository)
    when "cat_head_tail"
      entries = history_for_event(after_replay, event, repository)
      if action == "bank"
        return "cht-bank" if entries.any? { |entry| entry.kind == :bank }
        return nil
      end
      return nil if action != "roll"

      cues = ["cht-roll-dice"]
      cues << "cht-lost-points" if entries.any? { |entry| entry.kind == :lost_points }
      cues << "cht-cat-minus-8" if entries.any? { |entry| entry.kind == :cat_minus }
      cues << "cht-cat-plus-8" if entries.any? { |entry| entry.kind == :cat_plus }
      cues
    when "uno"
      event_history = history_for_event(after_replay, event, repository)
      return nil if event_history.any? { |entry| entry.key.to_s.start_with?("too_late:") }
      cues = []
      if action == "deal"
        cues << "shuffle"
      elsif action == "uno"
        cues << "buzzer2" if event_history.any? { |entry| entry.key.to_s.start_with?("uno:") }
      elsif %w[draw turn_timeout catch challenge].include?(action)
        cues << "draw"
      elsif action == "play"
        cues << "play"
        type = event["value"].to_s[1]
        cues << "skip" if type == "S"
        cues << "reverse3" if %w[V R].include?(type)
        cues << "reverse" if type == "L"
        cues << "buzzer" if type == "B" && event_history.any? { |entry| entry.kind == :play }
      end
      if event_history.any? { |entry| entry.key.to_s.start_with?("interception:") }
        cues << "interception"
      end
      round_result = event_history.find { |entry| entry.kind == :round_result }
      if round_result && GameRoomParticipants.includes?(after_replay.players, viewer)
        cues << (GameRoomParticipants.same?(round_result.actor, viewer) ? "win1" : "lose1")
      end
      cues
    when "makao"
      return "shuffle" if action == "deal"
      return "play" if action == "play"
      return "draw" if %w[draw catch].include?(action)
      if action == "makao_timeout"
        entries = history_for_event(after_replay, event, repository)
        return "draw" if entries.any? { |entry| entry.kind == :draw }
      end
      if action == "makao"
        event_history = history_for_event(after_replay, event, repository)
        return "buzzer2" if event_history.any? { |entry| entry.key.to_s.start_with?("makao:") }
      end
    when "rummy", "domino", "mexican_train"
      entries = history_for_event(after_replay, event, repository)
      deal_sound, draw_sound, play_sound = game.id.to_s == "rummy" ?
        %w[shuffle draw play] : %w[domino_refill domino_take_chip domino_move_tile]
      cues = []
      cues << deal_sound if entries.any? { |entry| entry.kind == :deal }
      cues << draw_sound if entries.any? { |entry| entry.kind == :draw }
      cues << play_sound if entries.any? { |entry| entry.kind == :play }
      result = entries.find { |entry| entry.kind == :round_result }
      if result && !result.actor.to_s.empty? && GameRoomParticipants.includes?(after_replay.players, viewer)
        winners = result.value.is_a?(Array) ? result.value : [result.actor]
        cues << (winners.any? { |p| GameRoomParticipants.same?(p, viewer) } ? "win1" : "lose1")
      end
      cues
    when "poker"
      return "shuffle" if action == "deal"
      return "draw" if action == "exchange" && !GameRoomTurnClock.payload(after_replay.state, event).empty?
      return "play" if action == "bet" && event["value"].to_s !~ /\A(?:check|fold)\|/
    when "yahtzee"
      return "roll" if action == "roll"
      return "play" if action == "score"
    when "monopoly"
      cues = []
      cues << "roll" if action == "roll"
      cues << "play2" if %w[buy build sell mortgage unmortgage trade_accept auction_bid].include?(action)
      event_history = history_for_event(after_replay, event, repository)
      cues << "hit1" if event_history.any? { |entry| entry.key.to_s.start_with?("group_complete:") }
      return cues.first if cues.length == 1
      return cues if !cues.empty?
    when "four_in_a_row"
      action == "drop" ? "play2" : nil
    when "tic_tac_toe"
      action == "place" ? "play2" : nil
    when "chess", "checkers"
      action == "move" ? "play2" : nil
    when "reversi"
      action == "place" ? "play2" : nil
    when "ludo"
      if action == "roll"
        moved_automatically = history_for_event(after_replay, event, repository).any? { |entry| entry.kind == :move }
        return moved_automatically ? ["roll", "play2"] : "roll"
      end

      ["move", "move_pawn"].include?(action) ? "play2" : nil
    when "quiz"
      quiz_cue(event, after_replay, repository, viewer)
    end
  end

  def quiz_cue(event, after_replay, repository, viewer)
    action = event["action"].to_s
    return "shuffle" if action == "round_draw"
    return "draw" if action == "round_category"
    return nil if action != "question_finished"

    answered_correctly = history_for_event(after_replay, event, repository).any? do |entry|
      entry.kind == :answer_result && entry.field.to_s == "right" &&
        GameRoomParticipants.same?(entry.actor, viewer)
    end
    answered_correctly ? "replay" : nil
  end

  def result_cue(game, before_replay, after_replay, viewer)
    # Initial reconstruction is silent. Permanent elimination is a transition,
    # not a property to announce again for every later move or final result.
    return nil if before_replay == nil || after_replay == nil || before_replay.finished?
    return nil if !GameRoomParticipants.includes?(after_replay.players, viewer)
    return nil if game.respond_to?(:eliminated_from_game?) && game.eliminated_from_game?(before_replay, viewer)

    # Resolve the final result first: a limit crossed on the final event may
    # still produce a winner (or a tie), depending on the game's rules.
    if after_replay.finished?
      return nil if after_replay.winner == nil || after_replay.draw
      reward = begin
        game.bot_reward(after_replay, viewer).to_f
      rescue StandardError
        GameRoomParticipants.same?(after_replay.winner, viewer) ? 1.0 : -1.0
      end
      return reward > 0 ? "win_party" : (reward < 0 ? "lose_party" : nil)
    end
    "lose_party" if game.respond_to?(:eliminated_from_game?) && game.eliminated_from_game?(after_replay, viewer)
  end

  def ninety_nine_cue(event, before_replay, after_replay, viewer)
    action = event["action"].to_s
    return "shuffle" if action == "deal"
    return "draw" if action == "draw"
    return nil if !["play", "play_draw"].include?(action)

    previous_total = before_replay&.state.to_h.fetch(:total, 0).to_i
    current_total = after_replay&.state.to_h.fetch(:total, previous_total).to_i
    viewer_played = GameRoomParticipants.same?(event["actor"], viewer)
    cues = ["play"]
    card, _mode = event["value"].to_s.split("|", 2)
    rank = card.to_s[1]
    cues << "reverse" if rank == "J"
    if rank == "4" && before_replay&.state.to_h.fetch(:eliminated, {}).count { |_player, eliminated| !eliminated } >= 3
      cues << "reverse3"
    end
    cues << "draw2" if [33, 66].any? { |limit| previous_total < limit && current_total > limit }
    cues << "ninety3366" if [33, 66].include?(current_total) && current_total > previous_total
    cues << (viewer_played ? "win1" : "lose1") if current_total == 99
    cues << (viewer_played ? "lose1" : "win1") if current_total > 99
    cues << "draw" if action == "play_draw"
    cues
  end

  def farkle_cue(event, before_replay, after_replay, repository)
    action = event["action"].to_s
    if action == "bank"
      return "farkle_bank" if history_for_event(after_replay, event, repository).any? { |entry| entry.kind == :bank }
      return nil
    end
    if action == "roll"
      return ["roll", "farkle"] if history_for_event(after_replay, event, repository).any? { |entry| entry.kind == :farkle }

      return "roll"
    end
    return nil if action != "keep"

    kept_count = event["value"].to_s.split(",").reject(&:empty?).length
    dice_before = before_replay&.state.to_h.fetch(:dice_to_roll, 0).to_i
    kept_count > 0 && kept_count == dice_before ? "replay" : nil
  end

  def history_for_event(replay, event, repository)
    event_id = repository.event_id(event).to_i
    replay.to_h.fetch(:history, []).to_a.select { |entry| entry.event_id.to_i == event_id }
  end

  def random_variant(names)
    # Cosmetic randomness must never consume the game's seeded RNG.
    @sound_random ||= Random.new
    names[@sound_random.rand(names.length)]
  end
end
