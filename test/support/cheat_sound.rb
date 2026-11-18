class CheatSoundProgram
  Voice = Struct.new(:volume, :done) do
    def finished?; done == true; end
    def closed?; false; end
  end
  attr_reader :played, :voices
  attr_accessor :optional, :volume
  def self.normalized_settings; {'background_game_sounds' => 'all'}; end
  def initialize; @played, @voices, @optional, @volume = [], [], true, 0.4; end
  def game_room_optional_sounds?; @optional; end
  def game_room_sound_volume(_name); @volume; end
  def play_sound_from_asset(name, volume:)
    raise 'Missing sound asset' unless File.file?(File.expand_path("../../Audio/#{name}.opus", __dir__))
    @played << [name, volume]
    Voice.new(volume).tap { |voice| @voices << voice }
  end
end
