# encoding: UTF-8
require 'fiddle'
require_relative '../game_room_localization'
require_relative 'bundled_braille_tables'
require_relative 'braille_catalog'

module GameRoomTyping
  class BrailleUnavailable < StandardError; end

  # Native Liblouis is optional. Never silently substitute a hard-coded
  # alphabet: it would give wrong answers for user-selected translation tables.
  class LibLouis
    using GameRoomLocalization::Translations
    DEFAULT_TABLES = BrailleCatalog::FILES
    TABLE_EXTENSIONS = %w[.ctb .utb .tbl .uti].freeze

    def self.discover(program: nil)
      bundled_root = BundledBrailleTables.new(program).materialize if program
      if bundled_root && RUBY_PLATFORM.match?(/mswin|mingw/i)
        arch = Fiddle::SIZEOF_VOIDP == 8 ? 'win64' : 'win32'
        return new(library_path: File.join(bundled_root, "liblouis-#{arch}.dll"), table_root: bundled_root, bundled_table_root: bundled_root)
      end
      roots = []
      if RUBY_PLATFORM.match?(/mswin|mingw|cygwin/i)
        roots += ['C:/Program Files/NVDA', 'C:/Program Files (x86)/NVDA']
      end
      roots.each do |root|
        library = File.join(root, 'liblouis.dll')
        tables = File.join(root, 'louis', 'tables')
        return new(library_path: library, table_root: tables, bundled_table_root: bundled_root) if File.file?(library) && File.directory?(tables)
      end
      %w[liblouis.so.20 liblouis.so liblouis.dylib liblouis.dll].each do |library|
        begin
          return new(library_path: library, bundled_table_root: bundled_root)
        rescue Fiddle::DLError
          next
        end
      end
      raise BrailleUnavailable, _('Liblouis is not installed.')
    rescue IOError, SystemCallError, Zlib::DataError, ArgumentError => exception
      raise BrailleUnavailable, _('Could not prepare braille tables: %{reason}') % {reason: GameRoomContent.utf8(exception.message)}
    end

    def initialize(library_path:, table_root: nil, bundled_table_root: nil)
      @library = Fiddle.dlopen(library_path)
      @table_root = table_root
      @bundled_table_root = bundled_table_root
      ptr = Fiddle::TYPE_VOIDP
      @char_size = Fiddle::Function.new(@library['lou_charSize'], [], Fiddle::TYPE_INT).call
      raise BrailleUnavailable, _('Unsupported Liblouis character width.') unless [2, 4].include?(@char_size)
      @translate = Fiddle::Function.new(@library['lou_translateString'],
        [ptr, ptr, ptr, ptr, ptr, ptr, ptr, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      @back_translate = Fiddle::Function.new(@library['lou_backTranslateString'], [ptr, ptr, ptr, ptr, ptr, ptr, ptr, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      @translate_positions = Fiddle::Function.new(@library['lou_translate'],
        [ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      @check = Fiddle::Function.new(@library['lou_checkTable'], [ptr], Fiddle::TYPE_INT)
    end

    def close
      @library.close
    end

    def tables
      labels = BrailleCatalog.labels
      DEFAULT_TABLES.filter_map do |id, filename|
        root = @bundled_table_root || @table_root
        filename = 'pl-pl-g1.utb' if id == 'polish_integral' && !@bundled_table_root
        path = root && File.join(root, filename)
        [id, labels.fetch(id), path] if path && File.file?(path)
      end
    end

    def table_path(id_or_path)
      item = tables.find { |id, _label, _path| id == id_or_path.to_s }
      path = item ? item[2] : File.expand_path(id_or_path.to_s)
      raise BrailleUnavailable, _('Choose an existing Liblouis table.') unless File.file?(path)
      raise BrailleUnavailable, _('Unsupported Liblouis table type.') unless TABLE_EXTENSIONS.include?(File.extname(path).downcase)
      raise BrailleUnavailable, _('The Liblouis table is too large.') if File.size(path) > 2_000_000
      raise BrailleUnavailable, _('The Liblouis table is invalid.') if @check.call(path + "\0") == 0
      path
    end

    def back_translate(cells, table:)
      path = table_path(table)
      encoding = @char_size == 2 ? Encoding::UTF_16LE : Encoding::UTF_32LE
      input = cells.encode(encoding)
      capacity = cells.length * 16 + 128
      output = "\0".b * (capacity * @char_size)
      input_length, output_length = [input.bytesize / @char_size].pack('l<'), [capacity].pack('l<')
      ok = @back_translate.call(path + "\0", input, input_length, output, output_length, 0, 0, 4 | 64)
      used = output_length.unpack1('l<')
      # A consumed standalone number/capital marker can successfully produce
      # no text. That is invalid word input, not a broken braille provider.
      raise BrailleUnavailable, _('Liblouis could not translate this word.') unless ok == 1 && used.between?(0, capacity) && input_length.unpack1('l<') == input.bytesize / @char_size
      output.byteslice(0, used * @char_size).force_encoding(encoding).encode(Encoding::UTF_8)
    end

    def translate(word, table: 'polish_integral')
      translation(word, table: table).first
    end

    # Output positions come from Liblouis, including contractions and markers.
    def source_position(word, cells:, table: 'polish_integral')
      return 0 if cells <= 0
      result, positions = translation(word, table: table, positions: true)
      return word.each_char.count if cells >= result.each_char.count
      units = positions.fetch(cells)
      encoding = @char_size == 2 ? Encoding::UTF_16LE : Encoding::UTF_32LE
      word.encode(encoding).byteslice(0, units * @char_size).force_encoding(encoding).encode(Encoding::UTF_8).length
    end

    private

    def translation(word, table:, positions: false)
      path = table_path(table)
      source = word.to_s
      raise ArgumentError, _('The word is too long for braille translation.') unless source.each_char.count.between?(1, 4096)

      encoding = @char_size == 2 ? Encoding::UTF_16LE : Encoding::UTF_32LE
      input = source.encode(encoding)
      input_count = input.bytesize / @char_size
      capacity = [input_count * 8 + 32, 128].max
      output = "\0".b * (capacity * @char_size)
      in_len = [input_count].pack('l<')
      out_len = [capacity].pack('l<')
      # dotsIO | ucBrl; output consists of Unicode braille cells, which can be
      # compared directly with eight-key chord input. Null typeform/spacing are
      # explicitly permitted by the Liblouis API.
      mapping = "\0".b * (capacity * 4) if positions
      ok = if positions
        @translate_positions.call(path + "\0", input, in_len, output, out_len, 0, 0, 0, mapping, 0, 4 | 64)
      else
        @translate.call(path + "\0", input, in_len, output, out_len, 0, 0, 4 | 64)
      end
      used = out_len.unpack1('l<')
      raise BrailleUnavailable, _('Liblouis could not translate this word.') unless ok == 1 && used.positive? && used <= capacity && in_len.unpack1('l<') == input_count

      result = output.byteslice(0, used * @char_size).force_encoding(encoding).encode(Encoding::UTF_8)
      raise BrailleUnavailable, _('The table did not produce braille cells.') unless result.each_char.all? { |cell| cell.ord.between?(0x2800, 0x28ff) }
      indices = mapping&.byteslice(0, used * 4)&.unpack('l<*')
      if indices && indices.any? { |index| !index.between?(0, input_count) }
        raise BrailleUnavailable, _('Liblouis could not translate this word.')
      end
      [result, indices]
    end
  end

  module SixKeyChord
    KEY_DOTS = { 'f' => 1, 'd' => 2, 's' => 3, 'j' => 4, 'k' => 5, 'l' => 6, 'a' => 7, ';' => 8 }.freeze

    def self.input?(character)
      character.match?(/\A(?:[\u2800-\u28ff]| |\x08)\z/)
    end

    def self.cell(keys)
      choices = keys.to_a.map { |key| KEY_DOTS[key.to_s.downcase] }
      return nil if choices.empty? || choices.any?(&:nil?)

      (0x2800 + choices.uniq.sum { |dot| 1 << (dot - 1) }).chr(Encoding::UTF_8)
    end
  end
end
