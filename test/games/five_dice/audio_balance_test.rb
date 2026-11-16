require 'json'
require 'digest'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

root = File.expand_path('../../..', __dir__)
originals = JSON.parse(File.read(File.join(root, 'test/fixtures/general_audio_original_hashes.json')))
gains = {''=>7.5, '_draw2'=>5.5, '_win1'=>-5.0, '_win2'=>1.5, '_lose3'=>-8.0}
crc = lambda do |bytes|
  value = 0
  bytes.each_byte do |byte|
    value ^= byte << 24
    8.times { value = ((value << 1) ^ (value[31] == 1 ? 0x04c11db7 : 0)) & 0xffffffff }
  end
  value
end

assert_equal(30, originals.length)
originals.each do |name, original_hash|
  suffix = name.sub(/\Akosciane_column_[1-6]/, '')
  bytes = File.binread(File.join(root, 'Audio', "#{name}.opus"))
  assert(bytes.start_with?('OggS'))
  header = 27 + bytes.getbyte(26)
  assert_equal('OpusHead', bytes.byteslice(header, 8))
  assert_equal((gains.fetch(suffix) * 256).round, bytes.byteslice(header + 16, 2).unpack1('s<'),
    "Wrong gain: #{name}")
  restored = bytes.dup
  restored[header + 16, 2] = [0].pack('s<')
  restored[22, 4] = "\0" * 4
  length = header + restored.byteslice(27, restored.getbyte(26)).bytes.sum
  restored[22, 4] = [crc.call(restored.byteslice(0, length))].pack('V')
  assert_equal(original_hash, Digest::SHA256.hexdigest(restored),
    "Audio packets, metadata, timing or layout changed instead of only gain: #{name}")
  position = 0
  while position < bytes.bytesize
    assert_equal('OggS', bytes.byteslice(position, 4))
    count = bytes.getbyte(position + 26)
    length = 27 + count + bytes.byteslice(position + 27, count).bytes.sum
    page = bytes.byteslice(position, length).dup
    checksum = page.byteslice(22, 4).unpack1('V')
    page[22, 4] = "\0" * 4
    assert_equal(checksum, crc.call(page), "Invalid Ogg checksum: #{name}")
    position += length
  end
  assert_equal(bytes.bytesize, position)
end
puts 'PASS General audio balance: all 30 calibrated gains, valid Ogg pages and byte-identical original compressed audio/tags/timing'
