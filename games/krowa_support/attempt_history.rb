# encoding: UTF-8
require 'base64'
require 'digest'
require 'json'
require 'openssl'

module GameRoomGames
  # Accepted words, independent of the current dictionary. Old results keep
  # their original spelling even after the vocabulary changes.
  module KrowaAttemptHistory
    MAX_BYTES = 4_194_304
    KEY = Digest::SHA256.digest('Power Games|Krowa attempt histories|v1').freeze
    module_function

    def rounds(replay)
      pending, result = {}, {}
      replay.accepted_events.each do |event|
        case event['action']
        when 'krowa_round'
          round = JSON.parse(event['value']).first
          result[round] = []
          pending.clear
        when 'krowa_guess'
          round, _ordinal, word = event['value'].split('|', 4)
          pending[(event['__id'] || event['id']).to_i] = [round.to_i, word]
        when 'krowa_score'
          round, request = event['value'].split('|', 3).map(&:to_i)
          trial = pending.delete(request)
          result.fetch(round) << trial.last if trial && trial.first == round
        end
      end
      result
    end

    def words(values, count: nil, solution: nil, solved: nil)
      raise ArgumentError, 'Invalid attempt list' unless values.is_a?(Array)
      list = values.map do |value|
        raise ArgumentError, 'Invalid attempt word' unless value.is_a?(String)
        word = value.dup
        word.force_encoding('UTF-8') if word.encoding == Encoding::BINARY
        raise ArgumentError, 'Invalid attempt word' unless word.valid_encoding? &&
          /\A[[:alpha:]]{3,13}\z/u.match?(word) && word == word.downcase
        word
      end
      raise ArgumentError, 'Attempt count differs' if count && list.length != count
      raise ArgumentError, 'Mixed word lengths' unless list.map(&:length).uniq.length <= 1
      if solution
        raise ArgumentError, 'Wrong attempt length' unless list.all? { |word| word.length == solution.length }
        raise ArgumentError, 'Missing winning attempt' if solved == true && list.last != solution
      end
      raise ArgumentError, 'Attempt list is too large' if JSON.generate(list).bytesize > MAX_BYTES / 4 * 3 - 64
      list
    end

    def identity(scope, list)
      Digest::SHA256.hexdigest(JSON.generate([scope, list]))
    end

    # Like DailyAssignment, this conceals answers in ordinary table data, not
    # from modified clients. Readers still enforce the confirmed server date.
    # Reuse a stored nonce only for the SAME content-addressed history so a
    # partially acknowledged upload can resume with identical immutable parts.
    def encode(scope, list, nonce: nil)
      cipher = OpenSSL::Cipher.new('aes-256-gcm').encrypt
      cipher.key = KEY
      iv = nonce ? Base64.strict_decode64(nonce) : cipher.random_iv
      cipher.iv = iv
      cipher.auth_data = JSON.generate([scope, identity(scope, list)])
      encrypted = cipher.update(JSON.generate(list)) + cipher.final
      [Base64.strict_encode64(cipher.auth_tag + encrypted), Base64.strict_encode64(iv)]
    end

    def decode(scope, key, payload, nonce)
      raise ArgumentError, 'Attempt list is too large' unless payload.bytesize <= MAX_BYTES
      bytes = Base64.strict_decode64(payload)
      raise ArgumentError, 'Invalid attempt payload' unless bytes.bytesize > 16
      cipher = OpenSSL::Cipher.new('aes-256-gcm').decrypt
      cipher.key = KEY
      cipher.iv = Base64.strict_decode64(nonce)
      cipher.auth_tag = bytes.byteslice(0, 16)
      cipher.auth_data = JSON.generate([scope, key])
      list = words(JSON.parse(cipher.update(bytes.byteslice(16..)) + cipher.final, max_nesting: 3))
      raise ArgumentError, 'Attempt history identity differs' unless identity(scope, list) == key
      list
    rescue OpenSSL::Cipher::CipherError, JSON::ParserError
      raise ArgumentError, 'Invalid attempt history'
    end
  end
end
