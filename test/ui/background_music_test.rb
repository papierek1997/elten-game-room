require_relative '../../lib/background_music'

class BackgroundSoundProbe
  attr_accessor :volume
  attr_reader :played, :closed
  def opened?; true; end
  def play; @played = true; end
  def close; @closed = true; end
end

tracks = {'general' => {'enabled' => true, 'file' => __FILE__, 'volume' => 20},
  'game' => {'enabled' => true, 'file' => __FILE__, 'volume' => 60}}
values = {'background_music' => tracks, 'sound_volumes' => {'all' => 50}}
sounds = []
music = GameRoomBackgroundMusic.new(settings: -> { values }, open_sound: ->(_path) { sounds << BackgroundSoundProbe.new; sounds.last })
music.enter
raise 'general not playing' unless sounds.last.played && sounds.last.volume == 0.1
music.enter
music.leave
raise 'nested form restarted music' unless sounds.size == 1 && !sounds.last.closed
owner = Object.new
music.game(owner, Struct.new(:finished?).new(false))
raise 'did not switch to game' unless sounds.size == 2 && sounds.first.closed && sounds.last.volume == 0.3
music.game(owner, Struct.new(:finished?).new(false))
raise 'replay restarted loop' unless sounds.size == 2
music.game(owner, Struct.new(:finished?).new(true))
raise 'did not restore general' unless sounds.size == 3 && sounds[1].closed
values['background_music']['general']['volume'] = 80
music.update
raise 'volume restarted stream' unless sounds.size == 3 && sounds.last.volume == 0.4
music.leave_game(owner)
music.leave
raise 'stream leaked on exit' unless sounds.last.closed
music.close
values['background_music']['general']['file'] = __FILE__ + '.missing'
music.enter
music.update
raise 'failed file retried on every update' unless sounds.size == 3
music.close
music.enter
one, two = Object.new, Object.new
values['background_music']['general']['file'] = __FILE__
music.game(one, Struct.new(:finished?).new(false))
music.game(two, Struct.new(:finished?).new(false))
shared = sounds.last
music.leave_game(one)
raise 'A second active game lost its background' unless sounds.last.equal?(shared) && !shared.closed
music.leave_game(two)
raise 'General did not return after last game' unless shared.closed
music.close
defaults = GameRoomPreferences.background_music({})
raise 'background enabled by default' if defaults.values.any? { |track| track['enabled'] }
invalid = GameRoomPreferences.background_music('background_music'=>{'general'=>{'file'=>"bad\0path",'enabled'=>true,'volume'=>0}})
raise 'Malformed file or explicit zero mishandled' unless invalid['general']['file']=='' && invalid['general']['volume']==0
attempts=0
retry_music=GameRoomBackgroundMusic.new(settings:-> {values},open_sound:->(_path) {
  attempts+=1
  raise IOError,'temporarily unavailable' if attempts==1
  BackgroundSoundProbe.new
})
retry_music.enter
retry_music.update
raise 'Failed stream retried without an explicit request' unless attempts==1
retry_music.update(retry_failed:true)
raise 'Explicit settings save could not retry an unavailable file' unless attempts==2
retry_music.close
puts 'Background music: local loops, nested forms, game transition, volume, cleanup and unavailable file passed.'
