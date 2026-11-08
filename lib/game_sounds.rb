require_relative "game_participants"
require_relative "game_turn_clock"
require_relative "game_sound_output"
require_relative "game_spatial_sound"

module GameRoomSounds
  ASSET_NAMES = %w[
    connect
    disconnect
    chatmsg
    notice
    table_notice
    invitation_rejected
    conference_created
    buzzer
    buzzer2
    quiz_wrong_answer
    bingo_draw
    roulette_spin
    roulette_chips
    duck_challenge
    duck_question
    duck_correct
    duck_frozen
    duck_final_lap
    war_open
    ding
    shuffle
    scopa
    scopa_deal
    scopa_take
    card-shuffle
    draw
    draw2
    bouillabaisse_rank
    bouillabaisse_card
    domino_refill
    domino_move_tile
    domino_take_chip
    farkle
    farkle_bank
    poker_fold
    poker_check
    poker_call
    poker_raise
    poker_all_in
    poker_pot
    cht-roll-dice
    cht-bank
    cht-lost-points
    cht-cat-minus-8
    cht-cat-plus-8
    ninety3366
    1000_mariage
    tysiac_surrender
    tysiac_contract_made
    tysiac_contract_failed
    mille_accident
    mille_distance_25
    mille_distance_50
    mille_distance_75
    mille_distance_100
    mille_distance_200
    mille_start
    mille_red_light
    mille_fuel_drain
    mille_driving_ace
    mille_right_of_way
    mille_dirty_trick
    mille_refuel
    mille_tire_puncture
    mille_wheel_change
    mille_puncture_proof
    mille_counterflow
    mille_repair
    mille_speed_limit
    mille_end_speed_limit
    mille_extra_tank
    mille_end_counterflow
    mille_instant_repair
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
    typing_error_1
    typing_error_2
    typing_error_3
    typing_error_4
    typing_error_5
    typing_endgame
    typing_survival_easy
    typing_survival_medium
    typing_survival_hard
  ].freeze

  BATTLESHIP_HITS = %w[hit_ship1 hit_ship2].freeze
  BATTLESHIP_LAUNCHES = %w[rocket_launch1 rocket_launch2 rocket_launch3].freeze
  # Balance the loud Battleship recordings before the user's volume controls.
  # Keep the audio files and playback handles intact for serial presentation.
  ASSET_VOLUME_GAINS = (BATTLESHIP_HITS + BATTLESHIP_LAUNCHES + ["rocket_miss"]).to_h { |name| [name, 0.2] }
    .merge("war_open" => 0.6, "duck_challenge" => 0.21811668, "duck_question" => 0.7, "mille_accident" => 0.7,
      "mille_right_of_way" => 0.8, "mille_driving_ace" => 0.75,
      "mille_distance_50" => 0.35, "mille_distance_75" => 0.35, "mille_distance_100" => 0.5,
      "mille_wheel_change" => 0.5, "mille_instant_repair" => 0.65,
      "mille_speed_limit" => 0.35, "mille_tire_puncture" => 0.8,
      "mille_extra_tank" => 0.7, "mille_end_counterflow" => 0.7).freeze

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

  def table_activity(program, entry, viewer:)
    return play(program, "chatmsg") if entry.kind == "chat" && !GameRoomParticipants.same?(entry.actor, viewer)
    return play(program, "conference_created") if entry.kind == "voice_started"
    if entry.kind == "invitation_rejected" && GameRoomParticipants.same?(entry.actor, viewer)
      play(program, "invitation_rejected")
    end
  end

  # `spatial` is an optional HRTF direction of the seat the cue belongs to.
  def play(program, name, spatial: nil)
    return nil if name == nil || !ASSET_NAMES.include?(name.to_s)
    if program.respond_to?(:game_room_sound_enabled?, true)
      return nil if !program.send(:game_room_sound_enabled?, name.to_s)
    end

    gain = ASSET_VOLUME_GAINS.fetch(name.to_s, 1.0)
    if program.respond_to?(:game_room_sound_volume, true)
      volume = program.send(:game_room_sound_volume, name.to_s) * gain
      return nil if volume <= 0

      play_asset(program, name.to_s, volume, spatial: spatial)
    else
      play_asset(program, name.to_s, gain, spatial: spatial)
    end
  rescue Exception => error
    Log.warning("ELTEN Game Room sound #{name} failed: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def play_all(program, names)
    names.to_a.each { |name| play(program, name) }
  end

  def play_asset(program, name, volume, spatial: nil)
    if %w[connect disconnect chatmsg notice table_notice invitation_rejected conference_created ding].include?(name)
      program.play_sound_from_asset(name, volume: volume)
    elsif spatial
      # The host returns nil when the 3D voice cannot start; stay audible.
      placed = volume * GameRoomSpatialSound.gain(spatial)
      (GameRoomSpatialSound.distant?(spatial) && GameRoomSpatialSound.play_distant(program, name, placed, spatial)) ||
        GameRoomSoundOutput.play(program, name, volume: placed, spatial: spatial) ||
        GameRoomSoundOutput.play(program, name, volume: volume)
    else
      GameRoomSoundOutput.play(program, name, volume: volume)
    end
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
  def event_cue(game:, event:, before_replay:, after_replay:, repository:, viewer:, history: nil, include_result: true)
    history ||= history_for_event(after_replay, event, repository)
    cues = Array(action_cue(
      game: game,
      event: event,
      before_replay: before_replay,
      after_replay: after_replay,
      repository: repository,
      viewer: viewer,
      history: history
    ))
    if history.any? { |entry| entry.kind == :reshuffle }
      cues.unshift("card-shuffle")
    end
    cues.concat(Array(result_cue(game, before_replay, after_replay, viewer))) if include_result
    cues = cues.compact.map(&:to_s).reject(&:empty?).uniq
    return nil if cues.empty?
    return cues.first if cues.length == 1

    cues
  end

  def action_cue(game:, event:, before_replay:, after_replay:, repository:, viewer:, history: nil)
    game.event_sound_cues(event: event, before_replay: before_replay,
      after_replay: after_replay, history: history || history_for_event(after_replay, event, repository),
      viewer: viewer, random_variant: method(:random_variant))
  end

  def result_cue(game, before_replay, after_replay, viewer)
    cue = default_result_cue(game, before_replay, after_replay, viewer)
    return cue unless game.respond_to?(:result_sound_cue)
    game.result_sound_cue(before_replay: before_replay, after_replay: after_replay,
      viewer: viewer, default_cue: cue)
  end

  def default_result_cue(game, before_replay, after_replay, viewer)
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
