require_relative '../../support/billiards'
require_relative '../../../lib/game_event_presenter'

module BilliardsSpatialAudioTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  class Program
    attr_accessor :hrtf, :enabled, :volume, :fail_spatial
    attr_reader :calls
    def initialize; @hrtf, @enabled, @volume, @calls = true, true, 0.4, []; end
    def game_room_hrtf?(_game); @hrtf; end
    def game_room_optional_sounds?; true; end
    def game_room_sound_enabled?(_name); @enabled; end
    def game_room_sound_volume(_name); @volume; end
    def play_sound_from_asset(asset, **options)
      @calls << [asset, options]
      @fail_spatial && options[:spatial] ? nil : Object.new
    end
  end
  def self.run
    table = B::Table.new
    left = B::SpatialAudio.position(table, kind: :rail, x: 0.0, y: 0.5)
    right = B::SpatialAudio.position(table, kind: :rail, x: table.width, y: 0.5)
    assert(left[0] < 0 && right[0] > 0 && left[2] < 0 && right[2] < 0)
    assert((left[0] + right[0]).abs < 1e-9, 'The listener was not centred on the lower cushion')
    assert_equal(0.0, left[1])
    assert((left.sum { |v| v*v } - 1).abs < 1e-9)
    assert_equal(nil, B::SpatialAudio.position(table, kind: :ball, x: Float::NAN, y: 1))
    assert(B::SpatialAudio.position(table, kind: :pocket, id: 0)[0] < 0)
    assert(B::SpatialAudio.position(table, kind: :pocket, id: 5)[0] > 0)
    match = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'friendly'})
    before = match.replay
    move = match.game.legal_actions(before, 'Alice').first
    after = match.submit('shot', move.reject { |k, _| %w[kind action revision].include?(k) })
    event = match.events.last
    stages = match.game.event_presentation_stages(event, match.repository, before, after, 'Alice')
    contact_stage = stages.find { |stage| stage[:history].any? { |entry| B::Presentation.cue(entry.value) == 'billiards_collision' } }
    assert(contact_stage, 'The real shot did not reach an object ball')
    original = Marshal.dump(after)
    program = Program.new
    old_ready = GameRoomSpatialSound.instance_variable_get(:@engine_ready)
    GameRoomSpatialSound.instance_variable_set(:@engine_ready, true)
    [:own, :opponent, :spectator, :covered].each do |perspective|
      viewer = {own:'Alice', opponent:'Bob', spectator:'Observer', covered:'Alice'}.fetch(perspective)
      presenter = GameRoomEventPresenter.new(game: -> { match.game }, repository: -> { match.repository },
        program: -> { program }, viewer: -> { viewer }, client: -> { nil }, surface_state: -> { {} },
        clock: -> { 1.0 }, covered: -> { perspective == :covered }, speech: ->(_text) {}, trace: ->(*) {},
        history_changed: ->(*) {}, session_changed: -> {})
      presenter.send(:present_game_event, event, before, after, after, nil, stage: contact_stage)
      asset, options = program.calls.last
      assert_equal('billiards_collision', asset)
      expected = B::SpatialAudio.position(table, contact_stage[:history].first.value)
      assert_equal(expected, options[:spatial], "#{perspective}: the source followed the player's seat instead of the physical contact")
      assert(!options.key?(:effect_buffer) && !options.key?(:sample), 'Billiards forced buffering or sampling options')
    end
    position = GameRoomSpatialSound.event_position(program, match.game, event, before, after, match.repository, 'Alice', {}, history: contact_stage[:history])
    assert_equal(nil, GameRoomSpatialSound.cue_position('win_party', position), 'The victory signal moved onto the table')
    program.hrtf = false
    assert_equal(nil, GameRoomSpatialSound.event_position(program, match.game, event, before, after, match.repository, 'Alice', {}, history: contact_stage[:history]))
    program.hrtf = true
    GameRoomSpatialSound.instance_variable_set(:@engine_ready, false)
    assert_equal(nil, GameRoomSpatialSound.event_position(program, match.game, event, before, after, match.repository, 'Alice', {}, history: contact_stage[:history]),
      'An unavailable HRTF engine was used')
    GameRoomSpatialSound.instance_variable_set(:@engine_ready, true)
    program.fail_spatial = true
    program.calls.clear
    GameRoomSounds.play(program, 'billiards_collision', spatial: left)
    assert_equal(2, program.calls.length)
    assert(!program.calls.last.last.key?(:spatial), 'A failed HRTF effect did not keep ordinary audio')
    program.enabled = false
    program.calls.clear
    GameRoomSounds.play(program, 'billiards_collision', spatial: left)
    assert_equal([], program.calls)
    assert_equal(original, Marshal.dump(after), 'Audio placement mutated the accepted model')
    copied = stages.first[:history].first.value
    copied[:x] = 999
    assert_equal(original, Marshal.dump(after), 'A presentation contact shared the model\'s mutable event')
    puts 'Billiards HRTF: real staged contacts through the shared presenter, physical left/right for players/spectators/covered views, settings, stereo fallback, unchanged buffering, copied models and centred results passed.'
  ensure
    GameRoomSpatialSound.instance_variable_set(:@engine_ready, old_ready) if defined?(old_ready)
  end
end
BilliardsSpatialAudioTest.run if $PROGRAM_NAME == __FILE__
