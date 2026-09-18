# encoding: UTF-8

module GameRoomKrowa
  module WordLength
    MINIMUM = 3
    MAXIMUM = 13

    module_function

    def valid?(word)
      word.to_s.length.between?(MINIMUM, MAXIMUM)
    end
  end
end
