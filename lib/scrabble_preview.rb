require 'securerandom'
require_relative 'game_room_background'
require_relative 'realtime/progress'

# A transient, public sketch, not a game move. Only placed letter faces leave
# the UI. The authoritative board/score/rack always comes from normal replay.
class GameRoomScrabblePreview
  using GameRoomLocalization::Translations
  INTERVAL = 0.12

  def initialize(program, game, transport:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, work: nil)
    @program, @game, @transport, @clock = program, game, transport, clock
    runtime = program.class.app_runtime if program.class.respond_to?(:app_runtime)
    @work = work || GameRoomBackground::Work.new(runtime: runtime)
    @stream, @sequence = SecureRandom.hex(8), 0
    @remote, @replies, @local = [], [], []
    @next_send = @next_tick = 0.0
  end

  def bind_screen(session_id:, table_id:, owner:, viewer:, members:)
    @session_id, @table_id, @viewer, @members = session_id, table_id, viewer, members
  end

  def start
    @progress = GameRoomRealtime::Progress.new(program: @program, clock: @clock,
      key: [:scrabble_preview, @table_id, @session_id, @viewer]) { tick }
    true
  end

  def update_table_control(session)
    @control = session['__control_epoch']
  end

  def before_wait(replay, _viewer)
    @replay = replay
    state = replay.state
    scope = [state[:revision], state[:current_player], @control]
    return if @scope == scope
    @scope = scope
    @remote, @local, @replies, @pending = [], [], [], nil
    @remote_stream, @remote_sequence = nil, 0
    @awaiting_snapshot = true
    @request_nonce, @request_attempts, @request_at = SecureRandom.hex(8), 0, 0.0
    queue_draft if author?
  end

  def attach_view(form, surface)
    # Private dealing and refill temporarily display the shared status list.
    # Keep progress attached, but bind drafts only to an actual word board.
    surface = nil unless surface.is_a?(GameSurfaces::WordBoardSurface)
    return if @surface.equal?(surface) && @form.equal?(form)
    @surface.on_draft_changed = nil if @surface
    @form, @surface = form, surface
    if @surface
      @surface.on_draft_changed = method(:draft_changed)
      draft_changed(@surface.public_draft) if author?
      @surface.remote_draft = @remote
    end
    @progress.attach(form)
  end

  def draft_changed(tiles)
    return if @closed || !author? || tiles == @local
    @local = tiles.map(&:dup)
    queue_draft
  end

  def tick
    return if @closed || !@replay || @clock.call < @next_tick
    now = @clock.call
    @next_tick = now + 0.025
    @transport.take_game_previews(@table_id, @session_id).each { |item| receive(item) }
    # The first snapshot is requested, not polled from the server. Retry only
    # an unanswered request, bounded and backed off, or after a changed scope.
    if playing? && !author? && @awaiting_snapshot && @request_attempts < 4 && now >= @request_at
      @pending = envelope.merge('request' => @request_nonce)
      @request_at = now + 2.0 ** (@request_attempts + 1)
      @request_attempts += 1
    end
    flush(now)
    @surface.remote_draft = @remote if @surface && !@progress.covered?
  end

  def action(_selection, _replay, _viewer); false; end
  def show_settings; @program.__send__(:toggle_scrabble_draft_speech); end
  def context_data; {}; end
  # Preview tiles update the existing surface, never rebuild the form.
  def refresh_due?; false; end
  def error(_status); end
  def automatic_error(_status); end
  def after_events(replay, viewer, context:); before_wait(replay, viewer); end
  def event(*); end

  def close
    return if @closed
    @closed = true
    @progress&.close
    @work.close
    @surface.on_draft_changed = nil if @surface
    @pending = @surface = @form = nil
  end

  private

  def playing?; @replay&.state&.[](:phase) == :playing; end
  def author?; playing? && GameRoomParticipants.same?(@scope[1], @viewer); end
  def envelope
    {'game' => 'scrabble', 'revision' => @scope[0], 'actor' => @scope[1], 'control' => @scope[2]}
  end

  def queue_draft
    @sequence += 1
    @pending = envelope.merge('stream' => @stream, 'sequence' => @sequence,
      'tiles' => @local.map(&:dup), 'replies' => @replies.dup)
  end

  def receive(item)
    data, sender = item[:payload], item[:sender]
    return unless playing? && data.is_a?(Hash) && envelope.all? { |key, value| data[key] == value }
    return unless @members.call.any? { |name| GameRoomParticipants.same?(name, sender) }
    if data.key?('request')
      return unless author? && token?(data['request'])
      @replies = (@replies + [data['request']]).uniq.last(8)
      queue_draft
      return
    end
    return if author? || !GameRoomParticipants.same?(sender, @scope[1])
    return unless token?(data['stream']) && data['sequence'].is_a?(Integer) && data['sequence'].between?(1, 2**53)
    return unless data['replies'].is_a?(Array) && data['replies'].size <= 8 && data['replies'].all? { |value| token?(value) }
    tiles = validated_tiles(data['tiles'])
    return unless tiles
    initial = @awaiting_snapshot || @remote_stream != data['stream']
    if @remote_stream != data['stream']
      # A delayed old stream cannot replace a new client's snapshot. A new
      # stream must first echo THIS receiver's fresh request nonce.
      unless data['replies'].include?(@request_nonce)
        if @remote_stream && !@awaiting_snapshot
          @request_nonce, @request_attempts, @request_at = SecureRandom.hex(8), 0, @clock.call
          @awaiting_snapshot = true
        end
        return
      end
      @remote_stream, @remote_sequence = data['stream'], 0
    end
    return if data['sequence'] <= @remote_sequence
    announce_changes(@remote, tiles) unless initial
    @remote_sequence, @remote = data['sequence'], tiles
    @awaiting_snapshot = false
  end

  def token?(value); value.is_a?(String) && value.match?(/\A[0-9a-f]{16}\z/); end

  def announce_changes(before, after)
    return unless @program.class.respond_to?(:normalized_settings) && @program.class.normalized_settings['scrabble_draft_speech'] == true
    return unless GameRoomBackgroundPolicy.speech?(@program, covered: @progress&.covered?)
    names = @program.local_name_presentation if @program.respond_to?(:local_name_presentation)
    player = names ? names.format(@scope[1], form: :first) : GameRoomParticipants.display_name(@scope[1])
    [[before - after, _('%{player} removes %{letter} from %{field}.')],
      [after - before, _('%{player} places %{letter} on %{field}.')]].each do |tiles, message|
      tiles.each do |tile|
        text = GameRoomContent.utf8(message) % {player: GameRoomContent.utf8(player),
          letter: tile[:letter].upcase, field: GameRoomScrabbleRules.field(tile[:position])}
        speak(text, stop: false, break_sequence: false)
      end
    end
  end

  def validated_tiles(tiles)
    return unless tiles.is_a?(Array) && tiles.size <= 7
    alphabet = @game.language(@replay.state).alphabet
    faces = @game.tiles(@replay.state).to_h { |tile| [tile[:letter], tile[:points]] }
    positions = []
    result = []
    tiles.each do |tile|
      return unless tile.is_a?(Array) && tile.size == 3
      pos, letter, blank = tile
      return unless pos.is_a?(Integer) && pos.between?(0, 224) && !positions.include?(pos) &&
        !@replay.state[:board][pos] && alphabet.include?(letter) && [true, false].include?(blank)
      positions << pos
      result << {position: pos, letter: letter, blank: blank, points: blank ? 0 : faces.fetch(letter)}
    end
    result
  end

  def flush(now)
    if (result = @work.take)
      _value, error = result
      if error
        Log.warning("ELTEN Game Room Scrabble preview: #{error.class}: #{error.message}") if defined?(Log)
        @failures = @failures.to_i + 1
        @pending ||= @sent if @failures < 3 && envelope.all? { |key, value| @sent[key] == value }
        @next_send = now + @failures
      else
        @failures = 0
      end
    end
    return if @work.busy? || !@pending || now < @next_send
    payload = @pending
    # There is only one in-flight request and one replaceable latest sketch.
    # Native send has a bounded timeout; failure never blocks a legal move.
    if GameRoomBackground.admit(@work) { @transport.send_game_preview(table_id: @table_id, session_id: @session_id,
        payload: payload, message_id: SecureRandom.uuid) }
      @sent = payload
      @pending = nil
      @next_send = now + INTERVAL
    end
  end
end
