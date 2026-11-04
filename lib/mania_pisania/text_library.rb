# encoding: UTF-8
require 'digest'
require 'json'
require_relative 'text'
require_relative 'languages'
require_relative '../game_room_localization'
require_relative '../../content/mania_pisania_texts'
require_relative '../../content/mania_pisania_texts_en'
require_relative '../../content/mania_pisania_texts_cs'
require_relative '../../content/mania_pisania_texts_es'
require_relative '../../content/mania_pisania_texts_ru'

module GameRoomTyping
  # Imported texts and reading progress remain in the local program data folder.
  # Importing is local; only an explicit multiplayer selection shares prose.
  class TextLibrary
    using GameRoomLocalization::Translations
    STORE = 'mania_pisania/texts.json'.freeze
    MAX_BYTES = 1_000_000
    BUILTIN = BuiltinTexts::STORIES.merge(
      BuiltinTextsEN::STORIES.transform_keys { |id| id + '_en' },
      BuiltinTextsCS::STORIES.transform_keys { |id| id + '_cs' },
      BuiltinTextsES::STORIES.transform_keys { |id| id + '_es' },
      BuiltinTextsRU::STORIES.transform_keys { |id| id + '_ru' }
    ).freeze

    def self.language
      %w[en pl cs es ru].include?(GameRoomLocalization.primary_language) ? GameRoomLocalization.primary_language : 'en'
    end

    def self.builtin_texts
      BUILTIN.select { |id, _| Languages.visible.include?(Languages.text_language(id)) }
    end

    def self.default_text
      builtin_texts.keys.find { |id| Languages.text_language(id) == language } || builtin_texts.keys.first
    end

    def initialize(program)
      @program = program
      raw = program.read_json(STORE, default: {})
      @records = raw.is_a?(Hash) && raw['texts'].is_a?(Hash) ? raw['texts'] : {}
      @progress = raw.is_a?(Hash) && raw['progress'].is_a?(Hash) ? raw['progress'] : {}
    end

    def entries
      builtin = self.class.builtin_texts.map { |id, item| entry("builtin:#{id}", item, imported: false) }
      imported = @records.filter_map do |id, item|
        entry(id, item, imported: true) if Languages.visible.include?(item.fetch('language', self.class.language))
      end
      builtin + imported.sort_by { |item| item['title'].downcase }
    end

    def fetch(id)
      key = id.to_s
      if key.start_with?('builtin:')
        BUILTIN[key.delete_prefix('builtin:')]
      else
        @records[key]
      end
    end

    def import_file(path)
      source = File.expand_path(path.to_s)
      raise ArgumentError, _('Choose a UTF-8 text file.') unless File.file?(source) && File.extname(source).downcase == '.txt'
      raise ArgumentError, size_limit_message if File.size(source) > MAX_BYTES

      text = File.binread(source).force_encoding(Encoding::UTF_8)
      import_text(text, title: File.basename(source, File.extname(source)))
    end

    def import_text(value, title: nil, update_title: false)
      text = value.to_s.dup.force_encoding(Encoding::UTF_8)
      raise ArgumentError, size_limit_message if text.bytesize > MAX_BYTES
      raise ArgumentError, _('The text file must be UTF-8.') unless text.valid_encoding?
      text = text.gsub("\r\n", "\n").strip
      raise ArgumentError, _('The file has no words.') if text.empty? || !text.match?(/\S+/)
      Document.new(text) # Validate and detect unsupported keyboard characters.

      id = "local:#{Digest::SHA256.hexdigest(text)}"
      label = GameRoomContent.utf8(title.to_s).strip
      label = _('Pasted text') if label.empty?
      return id if @records.key?(id) && (!update_title || @records[id]['title'] == label.each_char.take(150).join)
      records = @records.merge(id => { 'title' => label.each_char.take(150).join, 'text' => text,
        'language' => @records.dig(id, 'language') || self.class.language })
      persist!(records: records)
      @records = records
      id
    end

    def save_progress(id, snapshot)
      key = id.to_s
      return false if fetch(key) == nil

      progress = @progress.merge(key => snapshot.to_h.slice('position', 'correct_words', 'mistakes', 'active_seconds'))
      persist!(progress: progress)
      @progress = progress
      true
    end

    def progress_for(id)
      @progress.fetch(id.to_s, {})
    end

    def reset_progress(id)
      key = id.to_s
      return false unless fetch(key)

      progress = @progress.reject { |item, _| item == key }
      persist!(progress: progress)
      @progress = progress
      true
    end

    def remove(id)
      key = id.to_s
      return false unless @records.key?(key)

      records, progress = @records.reject { |id, _| id == key }, @progress.reject { |id, _| id == key }
      persist!(records: records, progress: progress)
      @records, @progress = records, progress
      true
    end

    private

    def size_limit_message
      _('Maximum text size: %{bytes} UTF-8 bytes (1000 kB).') % {bytes: MAX_BYTES}
    end

    def entry(id, item, imported:)
      text = item.fetch('text').to_s
      words = Document.new(text).tokens.length
      position = @progress.fetch(id, {}).fetch('position', 0).to_i
      { 'id' => id, 'title' => item.fetch('title').to_s, 'imported' => imported,
        'progress' => words.zero? ? 0.0 : (position.to_f / words * 100).round(1) }
    end

    def persist!(records: @records, progress: @progress)
      raise IOError, _('Could not save typing texts.') if @program.write_json(STORE, { 'texts' => records, 'progress' => progress }) == false
    end
  end
end
