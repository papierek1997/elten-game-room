# encoding: UTF-8
require 'digest'
require_relative 'text_library'

module GameRoomTyping
  using GameRoomLocalization::Translations
  # Public, bounded description of one exact source. Prose and filesystem
  # paths never enter table options or discovery/notification metadata.
  module TextSelection
    class Unavailable < ArgumentError; end
    KEYS = %w[text_id text_title text_characters text_sha256].freeze
    module_function

    def describe(id, item)
      text = Document.new(item.fetch('text')).text
      raise ArgumentError, _('The prepared text exceeds the UTF-8 byte limit.') if text.bytesize > TextLibrary::MAX_BYTES
      title = GameRoomContent.utf8(item.fetch('title')).gsub(/\s+/, ' ').strip
      if title.bytesize > 128
        shortened = +''
        title.each_char { |char| break if shortened.bytesize + char.bytesize > 125; shortened << char }
        title = shortened + '...'
      end
      {'text_id' => id, 'text_title' => title, 'text_characters' => text.length,
        'text_sha256' => Digest::SHA256.hexdigest(text)}
    end

    def descriptor(options)
      return nil unless options.is_a?(Hash)
      data = options.slice(*KEYS)
      return nil unless data.length == KEYS.length && data['text_id'].is_a?(String) &&
        data['text_id'].match?(/\A(?:local:[0-9a-f]{64}|builtin:[a-z_]+)\z/) &&
        data['text_title'].is_a?(String) && data['text_title'].valid_encoding? &&
        !data['text_title'].strip.empty? && data['text_title'].bytesize <= 128 &&
        !data['text_title'].match?(/[\r\n\t]/) && data['text_characters'].is_a?(Integer) &&
        data['text_characters'].between?(1, TextLibrary::MAX_BYTES) &&
        data['text_sha256'].is_a?(String) && data['text_sha256'].match?(/\A[0-9a-f]{64}\z/)
      data
    end

    def resolve(options, library)
      selected = descriptor(options)
      return nil unless selected
      item = library.fetch(selected['text_id'])
      return nil unless item && describe(selected['text_id'], item) == selected
      {'id' => selected['text_id'], 'title' => selected['text_title'], 'text' => Document.new(item['text']).text}
    end

    BUILTIN = TextLibrary::BUILTIN.to_h do |id, item|
      [id, describe("builtin:#{id}", item).transform_values { |value| value.freeze }.freeze]
    end.freeze
  end
end
