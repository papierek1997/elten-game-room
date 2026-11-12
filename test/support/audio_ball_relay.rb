require_relative 'relay'
require_relative 'audio_ball_client'

class AudioBallRelayHarness < AudioBallHarness
  attr_reader :rig

  def initialize(**options)
    @rig = RelayFixture.new
    @keys = {}
    super(**options)
  end

  def add_client(name, connected: true)
    rig = @rig
    program = Program.new
    program.define_singleton_method(:communication) { rig.endpoint(name) }
    program.define_singleton_method(:release) { |_resource| }
    @audios[name] = AudioBallTestAudio.new
    client = GameRoomAudioBall::Client.new(program, @game, clock: -> { @now }, audio: @audios[name],
      channel_factory: ->(**args) { @network[name.downcase] = GameRoomRealtime::EventChannel.new(**args,
        work_factory: -> { rig.worker(name) }, event_work_factory: -> { rig.worker(name) }) })
    client.bind_screen(session_id: 300, table_id: 20, owner: @owner, viewer: name, members: -> { @viewers })
    client.start
    client.before_wait(@replay, name)
    @surfaces[name] = GameSurfaces.build(@game.surface_spec(@replay, name))
    field = @surfaces[name].fields.first
    field.model_keyboard_input!
    @keys[name] = []
    keys = @keys
    field.define_singleton_method(:key_pressed?) { |code| keys[name].include?(code) }
    field.define_singleton_method(:key_held?) { |code| keys[name].include?(code) }
    @forms[name] = Form.new([field, EditBox.new('Chat')])
    client.attach_view(@forms[name], @surfaces[name])
    @clients[name] = client
    @viewers << name unless @viewers.include?(name)
    client
  end

  def advance(count = 1, seconds: 0.008, names: @viewers)
    count.times do
      @now += seconds
      @rig.now = @now
      @rig.advance_work
      names.each do |name|
        field = @surfaces[name].fields.first
        $activecontrols = [field]
        field.update
        @keys[name] = []
        @clients[name].frame
      end
    end
  ensure
    $activecontrols = nil
  end

  def key(name, command)
    @keys[name] = [{'up' => 0x57, 'left' => 0x44, 'down' => 0x53, 'prepare' => 0x41}.fetch(command)]
  end

  def press(name, *commands)
    commands.each { |command| key(name, command); advance; advance }
  end

  def wait_ready
    1500.times do
      advance
      return if @clients.values.none?(&:paused)
    end
    raise 'native Audio Ball channel never became ready'
  end

  def commit
    before = @replay.state[:rally]
    super
    @clients[@owner].instance_variable_get(:@bots).each do |bot|
      assert(bot.selected_lane == nil, 'durable point retained an armed bot lane')
    end
    raise 'native agreed point was not accepted by replay' unless @replay.state[:rally] == before + 1
    @surfaces.each { |name, surface| surface.update_spec(@game.surface_spec(@replay, name)) }
  end

  def autoplay_step
    @players.each_with_index do |name, side|
      next if GameRoomParticipants.bot?(name)
      client = @clients.fetch(name)
      engine = client.engine
      next if client.paused || !engine
      if engine.holder == side
        key(name, engine.phase == :waiting ? 'prepare' : %w[up left down][@replay.state[:rally] % 3])
      elsif engine.phase == :flying && engine.receiver == side && engine.hits < 8
        distance = (engine.position - (side == 0 ? 25.0 : 0.0)).abs
        key(name, engine.shot) if distance <= 1.4
      end
    end
    advance
    commit if @clients[@owner].context_data['audio_ball_point']
  end
end
