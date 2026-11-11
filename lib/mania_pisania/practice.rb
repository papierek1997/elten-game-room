# encoding: UTF-8
require 'digest'
require_relative 'typing_engine'
require_relative 'survival_stream'
require_relative 'word_prompt'
require_relative 'checkpoint'

module GameRoomTyping
  using GameRoomLocalization::Translations
  # Owns one player's fast local input. It never calls the network or UI. The
  # client drains semantic notices and submits a single immutable round result.
  class Practice
    using GameRoomLocalization::Translations
    attr_reader :engine, :buffer, :result, :text_id

    def initialize(options:, word_bank:, seed:, multiplayer:, text: nil, text_id: nil,
      progress: {}, translator: nil, table: 'polish_integral', recording_seconds: nil,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @options, @word_bank, @seed, @clock = options, word_bank, seed, clock
      @translator, @table, @multiplayer = translator, table, multiplayer
      @text_id = text_id
      @prompt = WordPrompt.new
      @notices, @buffer = [], +''
      @first_key_at = @started_at = nil
      @prior_typing_seconds = 0.0
      @spelling_help = false
      @own_text = free? && text == nil
      @written_text = +''
      if free?
        @engine = @own_text ? FreeWriting.new : FreeText.new(text, **progress.to_h.transform_keys(&:to_sym))
      else
        arguments = {word_source: word_bank, seed: seed, clock: clock,
          expected_transform: ->(word, index) { braille_at?(index) ? braille_spellings(word).values : word }}
        @engine = if survival?
          SurvivalStream.new(**arguments, difficulty: options.fetch('difficulty', 'easy'), recording_seconds: recording_seconds)
        else
          WordStream.new(**arguments, variant: options.fetch('variant'), key_interval: multiplayer ? WordStream::KEY_INTERVAL : nil)
        end
      end
    end

    def free?; @options['variant'] == 'free'; end
    def memory?; @options['variant'] == 'memory'; end
    def survival?; @options['variant'] == 'survival'; end
    def finished?; @result != nil; end
    def paused?; @paused == true; end
    def current_word; finished? ? nil : @engine.current_word; end
    def braille?; braille_at?(free? ? @engine.correct_words + @engine.mistakes : (memory? ? @engine.word_index : @engine.typed_words)); end
    def errors; free? ? @engine.mistakes : @engine.errors; end

    def select_braille_table(table)
      # Never reinterpret an unfinished cell sequence using a different code.
      @selected_table = table
      apply_selected_table unless paused? || (braille? && !@buffer.empty?)
    end

    def display_buffer
      # Native focus/navigation reads this text; keep raw cells only in the
      # engine buffer, where braille validation and deletion need them.
      text = braille? ? partial_braille_text(@buffer).to_s : @buffer
      @own_text ? @written_text + text : text
    end

    def echo_text(text, character:)
      return text unless braille?
      return nil unless character == ' ' || character == "\b" || character.match?(/\A[\u2800-\u28ff]\z/)
      return partial_braille_text(text) if character == ' '

      if character == "\b"
        current = partial_braille_text(@buffer)
        remaining = partial_braille_text(@buffer[0...-1])
        return current[remaining.length..] if current && remaining && current.start_with?(remaining)
        return partial_braille_text(text)
      end

      previous = partial_braille_text(@buffer).to_s
      current = partial_braille_text(@buffer + character)
      current && current.start_with?(previous) ? current[previous.length..] : current
    end

    def start
      return if @started_at
      @started_at = @clock.call
      if @engine.finished?
        finish
      else
        announce_prompt(initial: true)
      end
    end

    def prompt_finished
      @engine.prompt_finished(at: @clock.call) unless free? || finished?
    end

    def input(character)
      return if finished? || @started_at == nil || paused?
      now = @clock.call
      if free?
        if character == "\b"
          @buffer = @buffer[0...-1] unless @buffer.empty?
        elsif character == ' '
          return if @buffer.empty?
          previous_errors = @engine.mistakes
          typed = braille? && @own_text ? @translator.back_translate(@buffer, table: @table) : @buffer
          @written_text << typed << ' ' if @own_text
          expected = braille? && !@own_text ? braille_spellings(current_word).values : nil
          @engine.submit(typed, braille_expected: expected, first_key_at: @first_key_at || now, space_at: now, prior_seconds: @prior_typing_seconds)
          @prior_typing_seconds = 0.0
          @notices << [:error, _('Incorrect word.'), @engine.mistakes] if @engine.mistakes > previous_errors
          @buffer, @first_key_at = +'', nil
          @engine.finished? ? finish : announce_prompt unless @own_text
        elsif character.length == 1 && !character.match?(/\s/)
          @first_key_at ||= now
          @buffer << character
        end
      else
        previous_errors, previous_levels = @engine.errors, @engine.levels
        state = @engine.type(character, at: now)
        @buffer = @engine.buffer.dup
        error_notice if @engine.errors > previous_errors
        if state == :finished
          finish
        elsif state == :word
          if memory? && @engine.levels == previous_levels
            # No earlier word is re-read; the player recalls the whole chain.
            prompt_finished
          else
            announce_prompt
          end
        end
      end
      apply_selected_table if @buffer.empty? && !paused?
    end

    def tick
      return if finished? || @started_at == nil || paused?
      if free?
        minutes = @options.fetch('minutes', 0).to_i
        finish if minutes > 0 && @clock.call - @started_at >= minutes * 60
      else
        before = @engine.errors
        state = @engine.tick(at: @clock.call)
        @buffer = @engine.buffer.dup
        apply_selected_table if @buffer.empty?
        error_notice if @engine.errors > before
        @engine.finished? ? finish : announce_prompt if [:word, :finished].include?(state)
      end
    end

    def spell
      return nil unless help_word
      @spelling_help = true if memory?
      @prompt.spelling(help_word)
    end

    def repeat
      return nil unless help_word
      @spelling_help = true if memory?
      input_announcement + @prompt.announcement(help_word)
    end

    def remaining_sentence
      @engine.remaining_sentence if free? && !@own_text && !finished?
    end

    def remaining_word
      return nil if finished? || @own_text || memory?
      skipped = @buffer.each_char.count
      if braille?
        spelling = braille_spellings(current_word).find { |_word, cells| cells.start_with?(@buffer) }&.first || current_word.downcase
        skipped = @translator.source_position(spelling, cells: skipped, table: @table)
      end
      rest = current_word.each_char.drop(skipped).join
      rest.empty? ? _('The word is complete; press Space.') : @prompt.announcement(rest)
    end

    def help_started
      @engine.help_started(at: @clock.call) unless free? || finished?
    end

    def help_finished
      @engine.help_finished(at: @clock.call) unless free? || finished?
    end

    def snapshot(validate: true)
      if paused?
        data = Marshal.load(Marshal.dump(@pause_snapshot))
        raise ArgumentError, _('The typing checkpoint is too large or invalid.') if validate && !Checkpoint.valid?(data, variant: @options['variant'], seed: @seed)
        return data
      end
      now = @clock.call
      engine = free? ? @engine.snapshot.merge('mistakes' => @engine.mistakes) : @engine.snapshot(at: now)
      table = Checkpoint::TABLES.include?(@table) ? @table : 'custom'
      data = {'format' => Checkpoint::FORMAT, 'variant' => @options['variant'], 'seed' => @seed,
        'engine' => engine, 'buffer' => @buffer.dup, 'assisted' => @spelling_help, 'table' => table,
        'elapsed' => @started_at ? [now - @started_at, 0].max : 0.0,
        'partial_seconds' => @prior_typing_seconds + (@first_key_at ? [now - @first_key_at, 0].max : 0.0),
        'finished' => finished?, 'result' => @result}
      raise ArgumentError, _('The typing checkpoint is too large or invalid.') if validate && !Checkpoint.valid?(data, variant: @options['variant'], seed: @seed)
      data
    end

    def pause
      return if paused?
      tick
      # A local pause must still freeze timers if its later transport/export
      # validation fails. The host can safely cancel that pause without loss.
      @pause_snapshot = snapshot(validate: false)
      @paused = true
    end

    def restore(data)
      raise ArgumentError, _('Invalid typing checkpoint') unless Checkpoint.valid?(data, variant: @options['variant'], seed: @seed)
      @pause_snapshot = Marshal.load(Marshal.dump(data))
      @paused = true
    end

    def resume
      return unless paused?
      data = @pause_snapshot
      now = @clock.call
      if free?
        @engine.restore_snapshot(data.fetch('engine'))
        @prior_typing_seconds = data['partial_seconds']
        @first_key_at = nil
      else
        @engine.restore_snapshot(data.fetch('engine'), buffer: data['buffer'], at: now)
      end
      @buffer = data['buffer'].dup
      @spelling_help = data['assisted']
      @started_at = now - data['elapsed']
      @result = data['result']&.freeze if data['finished']
      @paused = false
      apply_selected_table if @buffer.empty? || !braille?
      @notices.clear
      announce_prompt(initial: true) unless finished?
    end

    def finish
      return if finished?
      if free?
        @result = {'words' => @engine.correct_words, 'errors' => @engine.mistakes,
          'wpm' => @engine.wpm, 'elapsed_ms' => (@engine.active_seconds * 1000).round,
          'levels' => 0, 'assisted' => false}
      else
        @engine.stop(at: @clock.call) unless @engine.finished?
        @result = @engine.result.merge('assisted' => @spelling_help)
      end
      @result.freeze
    end

    def take_notices
      value, @notices = @notices, []
      value
    end

    private

    def braille_spellings(word)
      [word.downcase, word, word.upcase, word.capitalize].uniq.to_h do |spelling|
        [spelling, @translator.translate(spelling, table: @table)]
      end
    end

    def apply_selected_table
      return unless @selected_table
      @table, @selected_table = @selected_table, nil
      @engine.reset_expected unless free?
    end

    def partial_braille_text(cells)
      return '' if cells.empty?
      @translator.back_translate(cells, table: @table)
    rescue BrailleUnavailable
      nil
    end

    def error_notice
      @notices << [:error, _('Errors: %{count} of 5.') % {count: @engine.errors}, @engine.errors]
    end

    def help_word
      return nil if finished?
      # Each new memory level restarts the recall cursor at word zero. The
      # prompt/help belongs to the new word, not to that earlier recalled word.
      memory? ? @engine.sequence.last : current_word
    end

    def braille_at?(index)
      mode = @options.fetch('input', 'keyboard')
      mode == 'braille' || (mode == 'mixed' && Digest::SHA256.digest("#{@seed}:#{index}").getbyte(0).odd?)
    end

    def input_announcement
      return '' unless @options['input'] == 'mixed'
      index = memory? ? @engine.sequence.length - 1 : nil
      braille = index ? braille_at?(index) : braille?
      braille ? _('Braille. ') : _('Keyboard. ')
    end

    def announce_prompt(initial: false)
      if free?
        if @own_text
          @notices << [:prompt, _('Type any text. End every word with Space.')]
          return
        end
        text = if initial || @engine.sentence_start?
          @engine.current_sentence + ' ' + input_announcement + @prompt.announcement(current_word)
        else
          input_announcement + @prompt.announcement(current_word)
        end
      elsif memory?
        text = input_announcement + @prompt.announcement(@engine.sequence.last)
      else
        text = input_announcement + @prompt.announcement(current_word)
      end
      @notices << [:prompt, text]
    end
  end

  class FreeWriting
    attr_reader :correct_words, :active_seconds
    def initialize; @correct_words = 0; @active_seconds = 0.0; end
    def current_word; nil; end
    def finished?; false; end
    def mistakes; 0; end
    def submit(_word, braille_expected: nil, first_key_at:, space_at:, prior_seconds: 0)
      @correct_words += 1
      @active_seconds += [space_at - first_key_at, 0].max + prior_seconds
    end
    def snapshot; {'position' => 0, 'correct_words' => @correct_words, 'mistakes' => 0, 'active_seconds' => @active_seconds}; end
    def restore_snapshot(data); @correct_words, @active_seconds = data.values_at('correct_words', 'active_seconds'); end
    def wpm; @active_seconds > 0 ? (@correct_words * 60.0 / @active_seconds).round(1) : 0.0; end
  end
end
