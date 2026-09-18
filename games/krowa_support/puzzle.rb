# encoding: UTF-8

module GameRoomKrowa
  Puzzle = Struct.new(:id, :solution, :mode, :metadata, keyword_init: true)
end
