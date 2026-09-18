# encoding: UTF-8

require_relative "errors"
require_relative "normalizer"

module GameRoomKrowa
  class SjpDefinitionProvider
    BASE_URL = "https://sjp.pl/"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    MAX_REDIRECTS = 3
    DEFINITION_PATTERN = %r{
      <p\b[^>]*>\s*<b>\s*znaczenie:\s*</b>.*?</p>\s*</div>\s*
      <p\b[^>]*>(.*?)</p>
    }imx.freeze

    def initialize(fetcher: nil)
      @fetcher = fetcher || method(:download)
      @cache = {}
    end

    def definition_for(word)
      normalized = Normalizer.call(word)
      return @cache[normalized] if @cache.key?(normalized)

      html = @fetcher.call(uri_for(normalized))
      definition = parse(html)
      @cache[normalized] = definition
    rescue DefinitionError
      raise
    rescue StandardError => error
      raise DefinitionError, error.message
    end

    def parse(html)
      match = DEFINITION_PATTERN.match(utf8_text(html))
      raise DefinitionNotFoundError, "Definition was not found on SJP" if match.nil?

      text = match[1]
        .gsub(%r{<br\s*/?>}i, "\n")
        .gsub(%r{<[^>]+>}, " ")
      text = unescape_html(text)
        .lines
        .map { |line| line.gsub(/[[:space:]]+/, " ").strip }
        .reject(&:empty?)
        .join("\n")
      raise DefinitionNotFoundError, "Definition on SJP was empty" if text.empty?

      text
    end

    private

    def utf8_text(value)
      text = value.to_s.dup
      # Net::HTTP returns response bodies as ASCII-8BIT even when the bytes
      # contain UTF-8. Mark those bytes before transcoding and sanitizing them.
      text.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::BINARY
      text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�").scrub
    end

    def uri_for(word)
      ensure_uri!
      encoded = word.encode(Encoding::UTF_8).bytes.map do |byte|
        character = byte.chr
        character.match?(/[A-Za-z0-9_.~-]/) ? character : format("%%%02X", byte)
      end.join
      URI("#{BASE_URL}#{encoded}")
    end

    def download(uri, redirects = MAX_REDIRECTS)
      begin
        require "net/http"
      rescue LoadError => error
        raise DefinitionError, "HTTP library is unavailable: #{error.message}"
      end
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Elten Krowa/0.4"
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) { |http| http.request(request) }

      case response
      when Net::HTTPSuccess
        utf8_text(response.body)
      when Net::HTTPRedirection
        raise DefinitionError, "Too many redirects from SJP" if redirects <= 0

        download(URI.join(uri, response["location"].to_s), redirects - 1)
      else
        raise DefinitionError, "SJP returned HTTP #{response.code}"
      end
    end

    def ensure_uri!
      return if defined?(URI)

      require "uri"
    rescue LoadError => error
      raise DefinitionError, "URI library is unavailable: #{error.message}"
    end

    def unescape_html(text)
      text.to_s
        .gsub(/&#(\d+);/) { valid_codepoint(Regexp.last_match(1).to_i) }
        .gsub(/&#x([0-9a-f]+);/i) { valid_codepoint(Regexp.last_match(1).to_i(16)) }
        .gsub("&nbsp;", " ")
        .gsub("&quot;", '"')
        .gsub("&apos;", "'")
        .gsub("&#39;", "'")
        .gsub("&lt;", "<")
        .gsub("&gt;", ">")
        .gsub("&amp;", "&")
    end

    def valid_codepoint(codepoint)
      [codepoint].pack("U")
    rescue RangeError
      "�"
    end
  end
end
