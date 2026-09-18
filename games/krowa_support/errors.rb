# encoding: UTF-8

module GameRoomKrowa
  class GuessError < StandardError
    attr_reader :code, :details

    def initialize(code, details = {})
      @code = code
      @details = details.freeze
      super(code.to_s)
    end
  end

  class StorageError < StandardError; end
  class ServerDateError < StandardError; end
  class DefinitionError < StandardError; end
  class DefinitionNotFoundError < DefinitionError; end
end
