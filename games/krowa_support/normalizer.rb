# encoding: UTF-8

module GameRoomKrowa
  module Normalizer
    module_function

    def call(value)
      value.to_s.strip.downcase
    end

    def letters_only?(value)
      word = call(value)
      !word.empty? && /\A[[:alpha:]]+\z/u.match?(word)
    end
  end
end
