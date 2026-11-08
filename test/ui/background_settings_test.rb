require_relative '../support/game_option_encoding'

class Sound
  def initialize(path, **options); @path = path; end
  def opened?; File.file?(@path); end
  def close; @closed = true; end
end
module Dirs
  def self.documents; File.expand_path('../..',__dir__); end
end
class BackgroundSettingsFixture < GameRoomScreens::Settings
  attr_accessor :selected_file
  def get_file(_title, **options)
    raise 'MIDI extensions missing' unless %w[.mid .midi .rmi .opus .mp3].all? { |ext| options[:extensions].include?(ext) }
    selected_file
  end
end

checks={forms:0,checkbox_states:0,labels:0}
%w[en pl ru].each do |language|
  $option_host_language=language
  GameRoomTestLocalization.use_language(language)
  values=GameRoomPreferences.defaults([])
  screen=BackgroundSettingsFixture.new(values,games:[],program:EltenGameRoom.allocate)
  screen.selected_file=__FILE__
  Form.option_encoding_driver=lambda do |form|
    categories=form.fields.first
    categories.index=3
    categories.trigger(:move)
    picks=form.fields.select { |f| f.is_a?(Button) && f.label.to_s.include?(':') }
    raise 'Two background file selectors missing' unless picks.size==2
    picks.each do |pick|
      pick.trigger(:press)
      index=form.fields.index(pick)
      form.fields[index-1].checked=true
      form.fields[index+1].index=27
    end
    GameOptionEncodingFixture.driver(checks).call(form)
  end
  updated=screen.wait
  tracks=updated.fetch('background_music')
  raise 'Background edits lost' unless tracks.values.all? { |track| track=={'enabled'=>true,'file'=>__FILE__,'volume'=>27} }
  raise 'Settings mutated before Save' if values.key?('background_music')
  Form.option_encoding_driver=->(form) { form.cancel_button.trigger(:press) }
  raise 'Cancel did not discard edits' unless screen.wait.nil?
end
puts "Background settings: two independent native file selectors, MIDI filters, Save/Cancel, encoding and #{checks[:forms]} EN/PL/RU focus checks passed."
