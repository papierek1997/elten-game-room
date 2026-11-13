require_relative "game_participants"
require_relative "game_sound_output"

# Optional HRTF placement of move sounds by seat or game-owned contact positions.
# In the seat mapping the listener sits at six o'clock; the next player is heard
# front-left and the rest follow clockwise to front-right (two players: the
# opponent in front; see FRONT_SPREAD). The listener's own sounds
# and table-wide cues stay ordinary centred stereo. Physical games can instead
# return a per-cue direction map for the current presentation stage.
module GameRoomSpatialSound
  # Steam Audio renders direction only; others sound slightly farther away.
  REMOTE_GAIN = 0.8
  # A source straight ahead loses the ear-level difference the side seats
  # have and sounds dull and quiet, so seats near 12 o'clock are lifted.
  FRONT_GAIN = 1.35
  # The seat straight ahead in these table sizes is heard across the table:
  # slightly raised (degrees above ear level), with softer highs and a room.
  DISTANT_TABLES = [2, 4, 6].freeze
  OPPONENT_ELEVATION = 5.0
  # Highs above this frequency (Hz) fade, and a small, light room is added.
  DISTANT_LOW_PASS = 9500.0
  DISTANT_REVERB = { dry_mix: 1.0, wet_mix: 0.3, room_size: 0.35, damping: 0.6, width: 1.0 }.freeze
  # Cues about the listener or the whole table, never about one seat.
  CENTRED_CUES = %w[win_party lose_party card-shuffle poker_pot].freeze
  # HRTF makes side seats sound farther sideways than they are and seats
  # behind sound odd, so the others share a front arc of this half-width in
  # degrees, by table size: three players about 11 and 1 o'clock, four about
  # 10, 12 and 2, five or more packed within 9:30 to 2:30.
  FRONT_SPREAD = { 3 => 30.0, 4 => 60.0, 5 => 75.0 }.freeze

  module_function

  # A unit direction for the source's seat, or nil when it is heard centred.
  def position(players, viewer, source)
    seats = GameRoomParticipants.unique(players)
    return nil if seats.length < 2 || source.to_s.empty?
    index = seats.index { |player| GameRoomParticipants.same?(player, source) }
    return nil if index == nil
    own = seats.index { |player| GameRoomParticipants.same?(player, viewer) }
    # A spectator listens from the first seat's chair without being seated.
    return nil if own == index
    step = (index - (own || 0)) % seats.length
    angle = Math::PI * seat_degrees(step, seats.length) / 180
    # A seat straight ahead otherwise sounds below ear level.
    across = own != nil && DISTANT_TABLES.include?(seats.length) && step == seats.length / 2
    lift = across ? Math::PI * OPPONENT_ELEVATION / 180 : 0.0
    [clean(-Math.sin(angle) * Math.cos(lift)), clean(Math.sin(lift)), clean(Math.cos(angle) * Math.cos(lift))]
  end

  # Degrees clockwise from behind the listener (90 left, 180 front, 270 right).
  # The others spread evenly over a front arc, left to right in seat order.
  def seat_degrees(step, count)
    return 0.0 if step == 0
    others = count - 1
    return 180.0 if others == 1
    spread = FRONT_SPREAD.fetch(count, FRONT_SPREAD.values.last)
    180.0 - spread + 2.0 * spread * (step - 1) / (others - 1)
  end

  def event_position(program, game, event, before_replay, after_replay, repository, viewer, session, history: nil)
    return nil if after_replay == nil || !enabled?(program, game)
    # Physical games place individual cue types using this stage's public contacts.
    return game.event_sound_positions(history: history, replay: after_replay) if game.respond_to?(:event_sound_positions)
    # The host can commit a shared event without being the source of its sound.
    return nil if game.respond_to?(:table_sound_event?) && game.table_sound_event?(event)
    source = repository.actor_of(event, session).to_s
    source = before_replay&.current_player.to_s if source.empty?
    position(after_replay.players, viewer, source)
  rescue StandardError => error
    Log.warning("ELTEN Game Room 3D sound position failed: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def enabled?(program, game)
    return false if game == nil || !game.respond_to?(:player_spatial_audio?) || !game.player_spatial_audio?
    return false unless program.respond_to?(:game_room_hrtf?, true) && program.send(:game_room_hrtf?, game.id)
    engine_ready?
  end

  def engine_ready?
    return @engine_ready unless @engine_ready.nil?
    @engine_ready = defined?(::Audio3DEffect) && ::Audio3DEffect.respond_to?(:load) && ::Audio3DEffect.load == true
  rescue StandardError
    @engine_ready = false
  end

  # Volume factor for a placed seat: REMOTE_GAIN at the sides, rising
  # steeply to FRONT_GAIN only close to straight ahead.
  def gain(position)
    level = Math.hypot(position[0].to_f, position[2].to_f)
    front = level > 0 ? [-position[2].to_f / level, 0.0].max : 0.0
    REMOTE_GAIN + (FRONT_GAIN - REMOTE_GAIN) * front**8
  end

  # Only the seat heard across the table (DISTANT_TABLES) is raised.
  def distant?(position)
    position[1].to_f > 0
  end

  # A seat straight ahead is otherwise hard to tell from the listener's own
  # sounds, so it gets a little room and softer highs, as if across the
  # table. Effects go on before playback so the start is clean.
  # Returns nil when the host cannot build the voice; the caller falls back.
  def play_distant(program, name, volume, position)
    return nil unless defined?(::ReverbEffect) && defined?(::BiquadFilterEffect) && ::BassFXEffect.available?
    return nil unless program.respond_to?(:create_spatial_sound_from_asset) && program.respond_to?(:sound_pool)
    sound = program.create_spatial_sound_from_asset(name, position: position)
    return nil if sound == nil
    sound.effect_add(::BiquadFilterEffect.new(filter: :low_pass, center: DISTANT_LOW_PASS))
    sound.effect_add(::ReverbEffect.new(**DISTANT_REVERB))
    GameRoomSoundOutput.apply(program, sound, volume, restart: true)
    program.sound_pool.play(sound)
  rescue StandardError => error
    Log.warning("ELTEN Game Room distant 3D sound failed: #{error.class}: #{error.message}") if defined?(Log)
    sound.close rescue nil if sound
    nil
  end

  def cue_position(cue, position)
    return nil if CENTRED_CUES.include?(cue.to_s)
    position.is_a?(Hash) ? position[cue.to_s] : position
  end

  def clean(value)
    value.abs < 1e-9 ? 0.0 : value
  end
end
