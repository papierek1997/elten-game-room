require_relative '../support/assertions'
require_relative '../../tools/support/release_files'
require 'open3'
include GameRoomTest::Assertions
root=File.expand_path('../..',__dir__)
files=GameRoomReleaseFiles.files(root)
%w[roulette_spin roulette_chips].each do |name|
  path="Audio/#{name}.opus"
  assert(files.include?(path),'Roulette sound omitted from release inputs')
  out,err,status=Open3.capture3('ffmpeg','-hide_banner','-i',File.join(root,path),'-af','volumedetect','-f','null','NUL')
  peak=err[/max_volume: (-?[0-9.]+) dB/,1]
  assert(status.success? && peak && peak.to_f > -40,"Roulette sound is silent or unreadable: #{name}")
end
assert(files.include?('LICENSES/ROULETTE-SOUNDS.txt'),'Roulette sound licence omitted from release inputs')
assert(files.include?('LICENSES/BINGO-SOUND.txt'),'Bingo sound licence omitted from release inputs')
puts 'Roulette audio: both Opus streams decode with audible signal, required assets and CC0 notices are included in release inputs; no package created.'
