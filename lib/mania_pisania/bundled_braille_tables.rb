# encoding: UTF-8
require 'base64'
require 'digest'
require 'fileutils'
require 'monitor'
require 'tempfile'
require 'zlib'
require_relative '../game_room_localization'
require_relative '../../content/mania_pisania_braille_tables'

module GameRoomTyping
  # Liblouis needs physical include files even when Elten loads the app from
  # a signed virtual package. Materialize only our embedded, checked content
  # in this app's cache, never in NVDA or in the user's original table folder.
  class BundledBrailleTables
    using GameRoomLocalization::Translations
    LOCK = Monitor.new

    def initialize(program)
      @program = program
    end

    def materialize
      root = @program.cache_path("mania_pisania/braille/#{BrailleTableData::CHECKSUM}")
      LOCK.synchronize do
        FileUtils.mkdir_p(root)
        BrailleTableData::FILES.each do |name, (checksum, encoded)|
          target = File.join(root, name)
          next if File.file?(target) && Digest::SHA256.file(target).hexdigest == checksum

          data = Zlib::Inflate.inflate(Base64.strict_decode64(encoded))
          raise BrailleUnavailable, _('Bundled braille table is damaged.') unless Digest::SHA256.hexdigest(data) == checksum
          Tempfile.create(['braille-', '.tmp'], root) do |temporary|
            temporary.binmode
            temporary.write(data)
            temporary.flush
            temporary.close
            File.rename(temporary.path, target)
          end
        end
      end
      root
    end
  end
end
