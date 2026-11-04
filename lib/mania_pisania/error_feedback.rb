# encoding: UTF-8
require_relative '../game_sounds'

module GameRoomTyping
  # Presentation policy is separate from counting errors. A text mistake
  # always uses error 2; word/chain errors use recordings 1 through 5.
  class ErrorFeedback
    def initialize(program, settings, speech:)
      @program, @settings, @speech = program, settings, speech
    end

    def present(text, count:, free:)
      if @settings['error_sounds']
        number = free ? 2 : count.to_i.clamp(1, 5)
        GameRoomSounds.play(@program, "typing_error_#{number}")
      end
      @speech.call(text) if @settings['error_speech']
    end
  end
end
