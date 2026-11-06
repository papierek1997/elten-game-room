require_relative "game_room_plural_rule"

module GameRoomLocalization
  module Translations
    refine Object do
      def _(source)
        GameRoomLocalization.translate(source)
      end

      def n_(singular, plural, count)
        GameRoomLocalization.translate(singular, plural: plural, count: count)
      end

      def p_(context, source)
        GameRoomLocalization.translate(source, context: context)
      end

      def np_(context, singular, plural, count)
        GameRoomLocalization.translate(singular, plural: plural, count: count, context: context)
      end
    end
  end

  class << self
    def boot(runtime: nil, directory: File.expand_path("../locale", __dir__), settings: nil, host_language: nil, known_languages: nil)
      runtime ||= Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime)
      host_language ||= Configuration.language if defined?(Configuration) && Configuration.respond_to?(:language)
      @catalogs = {}
      if runtime
        codes = (runtime.language_files.keys + runtime.manifest.supported_languages).map { |code| language_code(code) }.compact.uniq
        codes.reject { |code| code == "en" }.each { |code| add_catalog(code) { runtime.language_data(code) } }
        settings = runtime.read_json("settings.json", default: {}) if settings.nil?
      else
        Dir.glob("*.mo", base: directory).sort.each do |filename|
          path = File.join(directory, filename)
          code = language_code(File.basename(path, ".mo"))
          add_catalog(code) { File.binread(path) } if code && code != "en"
        end
      end
      @available_languages = (["en"] + @catalogs.keys).uniq.sort.map do |code|
        { id: code, label: language_name(code) }.freeze
      end.freeze
      @default_primary = language_code(host_language)
      @default_primary = "en" unless available_codes.include?(@default_primary)
      @default_known = known_languages.is_a?(Array) ? known_languages : []
      values = normalized_settings(settings)
      @translator = Translator.new(catalogs: @catalogs, primary: values.fetch("interface_language"), known: values.fetch("known_languages"))
      @translator
    end

    def available_languages
      boot unless @translator
      @available_languages
    end

    def normalize_settings(values)
      boot unless @translator
      normalized_settings(values)
    end

    def primary_language
      boot unless @translator
      @translator.primary
    end

    def known_languages
      boot unless @translator
      @translator.known.dup
    end

    # Opaque identity of the current catalogs and fallback-language settings.
    # Keep the object, not its object_id: a later boot may reuse an integer ID.
    def cache_token
      boot unless @translator
      @translator
    end

    def translate(source, **options)
      boot unless @translator
      @translator.translate(source, **options)
    end

    # Exact catalog forms, without changing the viewer's language or fallback
    # settings. Used to recognize automatic text stored by older clients.
    def translated_variants(source)
      boot unless @translator
      source = source.to_s.dup.force_encoding(Encoding::UTF_8)
      [source, *@catalogs.values.filter_map { |catalog| catalog.translate(source) }].uniq.freeze
    end

    private

    def language_code(value)
      value.to_s.downcase[/\A([a-z]{2,3})(?:[-_][a-z0-9-]+)?\z/, 1]
    end

    def available_codes
      @available_languages.map { |language| language.fetch(:id) }
    end

    def normalized_settings(values)
      source = values.is_a?(Hash) ? values : {}
      primary = language_code(source["interface_language"])
      primary = @default_primary unless available_codes.include?(primary)
      known = source["known_languages"].is_a?(Array) ? source["known_languages"] : @default_known
      requested = known.map { |code| language_code(code) }
      { "interface_language" => primary, "known_languages" => available_codes.select { |code| requested.include?(code) } }
    end

    def language_name(code)
      name = @catalogs[code]&.metadata&.fetch("X-Language-Name", nil)
      if name.to_s.empty? && defined?(Lists) && Lists.respond_to?(:langs)
        languages = Lists.langs
        record = languages[code] if languages.is_a?(Hash)
        name = record["nativeName"] if record.is_a?(Hash)
      end
      name = { "en" => "English", "pl" => "polski" }.fetch(code, code) if name.to_s.empty?
      name.to_s.dup.force_encoding(Encoding::UTF_8)
    end

    def add_catalog(code)
      data = yield
      @catalogs[code] = Catalog.new(data) if data
    rescue ArgumentError, IOError, SystemCallError => error
      Log.warning("Cannot load Game Room language #{code}: #{error.message}") if defined?(Log)
    end
  end

  class Catalog
    attr_reader :metadata

    def initialize(data)
      data = data.to_s.b
      raise ArgumentError, "invalid translation catalog" if data.bytesize < 28
      order = case data.byteslice(0, 4).unpack1("V")
      when 0x950412de then "V"
      when 0xde120495 then "N"
      else raise ArgumentError, "invalid translation catalog"
      end
      revision, count, originals, translations = data.byteslice(4, 16).unpack("#{order}4")
      if revision != 0 || [originals, translations].any? { |offset| offset < 28 || offset + count * 8 > data.bytesize }
        raise ArgumentError, "invalid translation catalog tables"
      end
      read = lambda do |table, index|
        length, offset = data.byteslice(table + index * 8, 8).unpack("#{order}2")
        raise ArgumentError, "truncated translation catalog" if offset + length > data.bytesize
        text = data.byteslice(offset, length).dup.force_encoding(Encoding::UTF_8)
        raise ArgumentError, "invalid translation encoding" unless text.valid_encoding?
        text
      end
      @entries = count.times.to_h do |index|
        [read.call(originals, index).split("\0").first.to_s, read.call(translations, index).split("\0", -1)]
      end
      @metadata = @entries.fetch("", []).first.to_s.lines.to_h do |line|
        name, value = line.split(":", 2)
        [name.to_s.strip, value.to_s.strip]
      end
      forms = @metadata.fetch("Plural-Forms", "nplurals=2; plural=(n != 1);")
      @plural_count = forms[/nplurals\s*=\s*(\d+)/, 1].to_i
      raise ArgumentError, "invalid plural form count" unless (1..16).include?(@plural_count)
      @plural_rule = PluralRule.new(forms[/\bplural\s*=\s*([^;]+)/, 1])
    end

    def translate(source, context: nil, count: nil)
      key = context ? "#{context}\u0004#{source}" : source
      index = count.nil? ? 0 : @plural_rule.index(count)
      return nil unless index.is_a?(Integer) && index >= 0 && index < @plural_count
      value = @entries[key]&.[](index)
      value.dup unless value.to_s.empty?
    end
  end

  class Translator
    attr_reader :primary, :known

    def initialize(catalogs:, primary:, known: [])
      @catalogs = catalogs
      @primary = primary.to_s
      @known = known.to_a.map(&:to_s).uniq
    end

    def translate(source, plural: nil, count: nil, context: nil, fallback_to_common: false)
      source = source.to_s.dup.force_encoding(Encoding::UTF_8)
      fallback = plural && count.to_i != 1 ? plural.to_s.dup.force_encoding(Encoding::UTF_8) : source
      ([@primary] + @known.reject { |language| language == "en" } + ["en"]).uniq.each do |language|
        return fallback if language == "en"
        translated = @catalogs[language]&.translate(source, context: context, count: count)
        if !translated && context && fallback_to_common
          translated = @catalogs[language]&.translate(source, count: count)
        end
        return translated if translated
      end
      fallback
    end
  end
end
