# frozen_string_literal: true

require_relative "../../lib/game_content"
require_relative "../../lib/game_room_localization"
require_relative "../../lib/game_participants"

module GameRoomDuckRacing
  # Accepts only the Engine's public, viewer-specific projection. It never
  # reads a model, dictionary, random stream, pending stimulus or clock.
  module ChallengePresentation
    using GameRoomLocalization::Translations
    module_function

    def project(kind:, view:, viewer:, previous_view: nil)
      raise ArgumentError, "Invalid challenge view" unless view.is_a?(Hash) && view[:type] == kind
      participants = view[:participants] || view[:seats] || []
      return observation(kind, view, previous_view) unless !viewer.nil? && participants.include?(viewer)
      return practice(kind, view, viewer, previous_view) if view[:practice]

      name, instruction, mode = description(kind)
      own = view[:own] || view[:own_result] || {}
      participants = view[:participants] || view[:seats] || []
      participating = !viewer.nil? && participants.include?(viewer)
      instruction = '' unless participating
      done = view[:finished] || own[:done] || own[:finished] || own[:phase] == :finished ||
        (view[:answered] && view[:answered][viewer])
      turn = current_turn(view)
      enabled = participating && !done && !view[:preparing] && !view[:session_paused] && (turn.nil? || turn == viewer)
      options, keys = list_options(kind, view)
      prompt = prompt(kind, view)
      digits = answer_digits(kind, view)
      instruction = [instruction, digit_hint(kind, view)].reject(&:empty?).join(' ') if participating
      status = status(kind, view, own, participating, done, turn, viewer)
      field_status = status(kind, view, own, participating, done, turn, viewer, playback_prompts: false)
      {
        name: text(name), instruction: text(instruction), mode: mode,
        header: [name, prompt, instruction, field_status].reject(&:empty?).map { |value| text(value) }.join(" "),
        status: text(status), announcement: text(announcement(kind, view, viewer, previous_view)),
        options: options.map { |value| text(value) }, option_keys: keys,
        enabled: !!enabled,
        # A phase transition suppresses keys already held, but a normal score,
        # attempt or draft refresh preserves both input and the native field.
        boundary: [kind, !!done, participating, turn, own[:phase], own[:level], own[:target_index], !!view[:preparing], !!view[:session_paused]],
        preparing: !!view[:preparing],
        session_paused: !!view[:session_paused],
        phase: own[:phase], playback_id: own[:playback_id], replays_left: own[:replays_left],
        auto_submit_length: digits,
        max_length: digits || 12
      }
    end

    # Both kinds of nonparticipant get the same read-only projection. Keep
    # private task hints out of the field AND the P reminder, not only speech.
    # Results still come from accepted history, never a local observer model.
    def observation_view(view)
      result = view.reject { |key, _| [:own, :own_result, :own_answer, :answer_digits, :attempt_limit, :preparing].include?(key) }
      result.delete(:question) unless %w[arithmetic race_question quiz].include?(view[:type])
      result.delete(:public) if %w[rhythm sound_order simon hit_duck].include?(view[:type])
      result.merge(observing: true)
    end

    def observation(kind, view, previous)
      view = observation_view(view)
      name = description(kind).first
      question = observation_prompt(kind, view)
      options, keys = %w[quiz numbered_balls].include?(kind) && !view[:practice] ? list_options(kind, view) : [[], []]
      status = observation_status(kind, view)
      initial = !previous.is_a?(Hash) || previous[:type] != kind || previous[:practice] && !view[:practice]
      notice = []
      notice << question if initial && !question.empty?
      if %w[rock_paper_scissors quiz].include?(kind)
        selected = observation_choices(view)
        selected -= observation_choices(previous) unless initial || !previous
        notice << (_('Already chosen: %{players}.') % {players: selected.join(', ')}) unless selected.empty?
      end
      {name: text(name), instruction: text(''), mode: options.empty? ? :button : :list,
        header: [name, question, status].reject(&:empty?).map { |value| text(value) }.join(' '),
        status: text(status), announcement: text(notice.join("\n")), options: options.map { |value| text(value) },
        option_keys: keys, enabled: false, boundary: [kind, :observer, !!view[:practice]],
        preparing: false, auto_submit_length: nil, max_length: 12}
    end

    def observation_prompt(kind, view)
      view[:question] && %w[arithmetic race_question quiz].include?(kind) ? prompt(kind, view) : ''
    end

    def observation_choices(view)
      chosen = view[:answered] || view[:ready] || {}
      chosen.filter_map do |seat, ready|
        text(GameRoomParticipants.display_name(view[:player_names].fetch(seat))) if ready && view[:player_names]&.key?(seat)
      end
    end

    def observation_status(kind, view, totals: false)
      parts = [_('You are watching.')]
      turn = current_turn(view)
      if !turn.nil? && view[:player_names]&.key?(turn)
        parts << (_("%{player}'s turn.") % {player: text(GameRoomParticipants.display_name(view[:player_names].fetch(turn)))})
      end
      chosen = observation_choices(view) if %w[rock_paper_scissors quiz].include?(kind)
      parts << (_('Already chosen: %{players}.') % {players: chosen.join(', ')}) if chosen && !chosen.empty?
      if totals && kind == 'numbered_balls'
        view.fetch(:scores, {}).each do |seat, score|
          next unless view[:player_names]&.key?(seat)
          parts << (_('%{player}: %{result}.') % {player: text(GameRoomParticipants.display_name(view[:player_names].fetch(seat))), result: score})
        end
      end
      parts.join(' ')
    end

    def description(kind)
      case kind
      when "rock_paper_scissors"
        [_('Rock, paper, scissors.'), _('Choose with the arrow keys, then press Enter.'), :list]
      when "dice_duel"
        [_('Dice duel.'), _('Press Enter to roll.'), :button]
      when "blackjack"
        [_('Twenty-one.'), _('Press Space to draw a card or Enter to keep your cards.'), :button]
      when "risky_dice"
        [_('Risky dice.'), _('Reach at most 25. Enter rolls the dice. Down, then Enter saves your result.'), :list]
      when "guess_number"
        [_('Guess the number.'), _('Number from 1 to 999.'), :text]
      when "copy_number"
        [_('Copy the number.'), '', :text]
      when "arithmetic"
        [_('Mental arithmetic.'), '', :text]
      when "race_question"
        [_('Race question.'), '', :text]
      when "numbered_balls"
        [_('Numbered balls.'), _('Browse the balls with the arrow keys. Press 1, 2 or 3 to take that many from the beginning.'), :list]
      when "count_ducks"
        [_('Count the ducks.'), _('F5 repeats the sounds.'), :text]
      when "rhythm"
        [_('Repeat the rhythm.'), _('Listen, press Enter, then repeat with F and J. F5 repeats the pattern before you start.'), :button]
      when "sound_order"
        [_('Order the sounds.'), _('Order the sounds from low to high. Keys 1 to 8 play them; Shift+digit selects two to swap.'), :button]
      when "audio_ball"
        [_('Audio Ball') + '.', '', :button]
      when "axel_pong"
        [_('Axel Pong') + '.', _('Win one point. Move your racket with Left and Right; press Up or Space to serve or return the ball. Press Enter when you are ready.'), :button]
      when "simon"
        [_('Simon.'), _('Listen, then repeat the sounds with 1 to 5. Press each key separately.'), :button]
      when "sound_memory"
        [_('Sound memory.'), _('Use the digits from 1 through 0 to reveal sounds. Reveal two on your turn and try to find a matching pair.'), :button]
      when "hit_duck"
        [_('Hit the duck.'), _('Press 1 to 9 where you hear the duck: 1 is left, 5 is centre, 9 is right.'), :button]
      when "quiz"
        [_('Quiz question.'), _('Choose an answer with 1 to 4, or use the arrow keys and Enter.'), :list]
      else
        raise ArgumentError, "Unknown non-realtime challenge: #{kind}"
      end
    end

    def practice(kind, view, viewer, previous)
      participating = view.fetch(:seats).include?(viewer)
      ready = view.dig(:own, :ready)
      instruction = case kind
      when 'simon' then _('Try the sounds with keys 1 to 5. Enter or Space starts the challenge.')
      when 'hit_duck' then _('Try the duck positions with keys 1 to 9, from left to right. Enter or Space starts the challenge.')
      when 'rhythm' then _('Try the two drum sounds with F and J. Enter or Space starts the challenge.')
      when 'audio_ball' then _('Try the ball sounds: W or Up for high, D or Left for middle, S or Down for low. Enter or Space confirms you are ready.')
      when 'axel_pong' then description(kind)[1]
      when 'sound_memory' then memory_instruction(view)
      else raise ArgumentError, 'Unknown practice challenge'
      end
      instruction = _('Waiting for others.') if ready
      if ready && view[:waiting]&.any? && view[:player_names]
        names = view[:waiting].map { |seat| text(GameRoomParticipants.display_name(view[:player_names].fetch(seat))) }.join(', ')
        instruction = _('Ready. Waiting for: %{players}.') % {players: names}
      end
      instruction = _('You are watching.') unless participating
      instruction = _('Game paused.') if view[:session_paused]
      message = !previous&.[](:practice) || previous.dig(:own, :ready) != ready ||
        ready && previous[:waiting] != view[:waiting] ? instruction : ''
      {name: text(description(kind).first), instruction: text(instruction), mode: :button,
        header: text(instruction), status: '', announcement: text(message), options: [], option_keys: [],
        enabled: participating && !ready && !view[:session_paused], boundary: [kind, :practice, participating, !!ready, !!view[:session_paused]],
        practice: true, phase: :practice, preparing: false}
    end

    def answer_digits(kind, view)
      return unless %w[copy_number guess_number arithmetic race_question count_ducks].include?(kind)

      if kind == 'copy_number'
        number = view.fetch(:question).fetch(:number).to_s
        raise ArgumentError, 'Copy number requires a public decimal number' unless number.match?(/\A[0-9]+\z/)
        number.length
      else
        digits = view.fetch(:answer_digits)
        raise ArgumentError, 'Invalid numeric answer width' unless digits.is_a?(Integer) && digits.between?(1, 9)
        digits
      end
    end

    def digit_hint(kind, view)
      return '' if kind == 'copy_number'
      digits = answer_digits(kind, view)
      digits ? n_('Answer: %{count} digit.', 'Answer: %{count} digits.', digits) % {count: digits} : ''
    end

    def list_options(kind, view)
      case kind
      when "rock_paper_scissors"
        [[_('Rock'), _('Paper'), _('Scissors')], %w[rock paper scissors]]
      when "risky_dice"
        [[_('Roll'), _('Save result')], %w[roll save]]
      when "numbered_balls"
        balls = view.fetch(:remaining)
        [balls.map(&:to_s),
          balls.each_index.map { |index| 12 - balls.length + index }]
      when "quiz"
        [view.fetch(:question).fetch(:choices).map { |choice| text(choice) }, (0..3).to_a]
      else
        [[], []]
      end
    end

    def prompt(kind, view)
      case kind
      when "copy_number"
        _('Number: %{number}.') % {number: view.fetch(:question).fetch(:number)}
      when "arithmetic"
        question = view.fetch(:question)
        template = {add: _('%{left} plus %{right}.'), subtract: _('%{left} minus %{right}.'),
          multiply: _('%{left} times %{right}.'), divide: _('%{left} divided by %{right}.')}.fetch(question.fetch(:operation))
        template % question.slice(:left, :right)
      when "race_question"
        question = view.fetch(:question)
        name = view.dig(:player_names, question.fetch(:seat))
        name = GameRoomParticipants.display_name(name) unless name.nil?
        name = _('Player %{number}') % {number: question.fetch(:seat) + 1} if name.nil?
        template = {square: _('Which square is %{player} on?'), lap: _('Which lap is %{player} on?'),
          feathers: _('How many feathers does %{player} have?'), card_count: _('How many cards does %{player} have?')}.fetch(question.fetch(:field))
        template % {player: text(name)}
      when "quiz"
        text(view.fetch(:question).fetch(:prompt))
      else
        ''
      end
    end

    def reminder(kind, view)
      if view[:observing]
        return [description(kind).first, observation_prompt(kind, view), observation_status(kind, view, totals: true)]
          .reject(&:empty?).join(' ')
      end
      return memory_instruction(view) if kind == 'sound_memory'
      question = prompt(kind, view)
      return question unless question.empty?

      if kind == 'guess_number'
        own = view[:own] || {}
        [_('Number from 1 to 999.'), digit_hint(kind, view),
          status(kind, view, own, true, false, nil, nil)].reject(&:empty?).join(' ')
      else
        description(kind).first(2).reject(&:empty?).join(' ')
      end
    end

    def memory_instruction(view)
      message = description('sound_memory')[1]
      message += ' ' + _('Press Enter when you are ready.') if view[:practice]
      message
    end

    def status(kind, view, own, participating, done, turn, viewer, playback_prompts: true)
      phase = phase_status(view, participating, done, turn, viewer)
      unless phase.empty?
        # A short spoken transition must not remove the hand or matched
        # positions from the field when a player finishes or waits for a turn.
        details = inspection_details(kind, view, own, participating)
        return [phase, details].reject(&:empty?).join(' ')
      end

      messages = []
      if playback_prompts && own[:phase] == :listening
        messages << _('Listen.')
      elsif kind == "rhythm" && own[:phase] == :ready
        messages << _('Press Enter to begin.')
      elsif own[:phase] == :responding
        messages << _('Repeat.') if playback_prompts && kind == 'simon'
        messages << _('Your answer.') if kind == 'hit_duck'
      end
      case kind
      when "dice_duel", "risky_dice"
        rolls = own[:rolls].to_a
        messages << (_('Roll: %{roll}. Total: %{total}.') % {roll: Array(rolls.last).join(', '), total: own[:total]}) unless rolls.empty?
      when "blackjack", "numbered_balls"
        messages << inspection_details(kind, view, own, participating)
      when "guess_number"
        attempt = own[:attempts].to_a.last
        if attempt
          messages << {higher: _('The number is higher.'), lower: _('The number is lower.'), correct: _('Correct.')}.fetch(attempt[:feedback])
        end
        messages << attempts_left(10 - own[:attempts].to_a.length)
      when "copy_number", "arithmetic", "race_question"
        attempts = own[:attempts].to_a
        messages << _('Incorrect answer.') if !attempts.empty? && !attempts.last[:correct]
        messages << attempts_left(view.fetch(:attempt_limit) - attempts.length)
      when "count_ducks"
        messages << attempts_left(2 - own[:attempts].to_i)
      when "simon"
        messages << (n_('%{count} sound', '%{count} sounds', own[:level]) % {count: own[:level]}) + '.' if playback_prompts && own[:level]
      when "sound_memory"
        messages << inspection_details(kind, view, own, participating)
      when "hit_duck"
        messages << (_('Target %{number} of 5.') % {number: own[:target_index].to_i + 1})
      end
      messages.reject(&:empty?).map { |message| text(message) }.join(' ')
    end

    def phase_status(view, participating, done, turn, viewer)
      return _('Game paused.') if view[:session_paused]
      return _('Challenge finished.') if view[:finished]
      return _('You are watching.') unless participating
      return _('Answer sent.') if done && %w[copy_number arithmetic race_question count_ducks].include?(view[:type])
      return _('Waiting for others.') if done
      return _('Waiting for your turn.') if !turn.nil? && turn != viewer
      ''
    end

    def inspection_details(kind, view, own, participating)
      if %w[dice_duel risky_dice].include?(kind) && participating && !own[:rolls].to_a.empty?
        _('Roll: %{roll}. Total: %{total}.') % {roll: Array(own[:rolls].last).join(', '), total: own[:total]}
      elsif kind == 'blackjack' && participating && own.key?(:card_ranks)
        _('Cards: %{cards}. Total: %{total}.') % {
          cards: own[:card_ranks].map { |rank| card_rank(rank) }.join(', '), total: own[:total]}
      elsif kind == 'sound_memory' && !view.dig(:public, :removed).to_a.empty?
        _('Matched positions: %{positions}.') % {positions: view[:public][:removed].join(', ')}
      elsif kind == 'numbered_balls' && participating
        _('Your total: %{total}.') % {total: own.fetch(:total)}
      else
        ''
      end
    end

    # Automatic speech describes only the latest change. The complete status
    # remains in the field; neither projection retains a model or a cursor.
    def announcement(kind, view, viewer, previous)
      unless previous.is_a?(Hash) && previous[:type] == kind
        own = view[:own] || view[:own_result] || {}
        return '' if view[:finished] || own[:done] || own[:finished] || own[:phase] == :finished ||
          view.dig(:answered, viewer)

        return initial_announcement(kind, view, viewer)
      end
      own, before = view[:own] || view[:own_result] || {}, previous[:own] || previous[:own_result] || {}
      participating = !viewer.nil? && (view[:participants] || view[:seats] || []).include?(viewer)
      if kind == 'count_ducks' && participating && own[:phase] == :responding && before[:phase] == :listening
        return digit_hint(kind, view)
      end
      turn_notice = turn_announcement(kind, view, viewer, previous)
      return '' if %w[numbered_balls sound_memory].include?(kind) # the shared presenter names the next player
      return '' if kind == 'hit_duck' # shot quality is spoken after the recording, not over it
      # Public card/dice actions are spoken once through accepted history,
      # for everyone. The local field keeps the hand/total for inspection.
      # Memory choices have transient speech synchronized with each sound,
      # not a recap of complete pairs or entries in the game history.
      return turn_notice if %w[dice_duel risky_dice blackjack].include?(kind)
      return turn_notice unless turn_notice.empty?

      current_status = announcement_status(kind, view, viewer)
      current_status == announcement_status(kind, previous, viewer) ? '' : current_status
    end

    def autoplay?(kind)
      %w[count_ducks rhythm simon hit_duck].include?(kind)
    end

    def memory_feedback(event, players)
      result = {announcement: _('%{player}: %{position}.') % {
        player: text(GameRoomParticipants.short_name(players.fetch(event.fetch(:seat)))),
        position: event.fetch(:position)}}
      result[:result_announcement] = event[:matched] ? _('Correct!') : _('Wrong!') if event.key?(:matched)
      result
    end

    def shot_quality(score)
      {100 => _('Perfect!'), 75 => _('Good!'), 50 => _('Fair!'),
        25 => _('Poor!'), 0 => _('Miss!')}.fetch(score)
    end

    def initial_announcement(kind, view, viewer)
      _name, instruction, = description(kind)
      participating = !viewer.nil? && (view[:participants] || view[:seats] || []).include?(viewer)
      # Accepted history announces the challenge name. Keep it in the field's
      # header for manual inspection, but do not repeat it on automatic entry.
      return '' if kind == 'sound_memory' # readiness explains controls; the shared event names the starter
      return _('You are watching.') unless participating
      # These four tasks start with their sound stimulus. The automatic first
      # focus must not talk over it; intentional focus/help still has controls.
      return '' if autoplay?(kind)

      question = prompt(kind, view)
      unless question.empty?
        return question if %w[quiz copy_number].include?(kind)
        return [question, digit_hint(kind, view)].reject(&:empty?).join(' ')
      end

      own = view[:own] || view[:own_result] || {}
      turn = current_turn(view)
      details = kind == 'blackjack' ? '' : inspection_details(kind, view, own, participating)
      choice = list_options(kind, view).first.first.to_s
      phase = phase_status(view, participating, false, turn, viewer)
      [instruction, digit_hint(kind, view), details, phase, choice].reject(&:empty?).join(' ')
    end

    def turn_announcement(kind, view, viewer, previous)
      return '' unless %w[dice_duel blackjack risky_dice numbered_balls sound_memory].include?(kind) && !viewer.nil? && !view[:finished]
      current = current_turn(view)
      before = current_turn(previous)
      current == viewer && current != before ? _('Your turn.') : ''
    end

    def current_turn(view)
      view.key?(:turn_seat) ? view[:turn_seat] : view.dig(:public, :turn)
    end

    def announcement_status(kind, view, viewer)
      own = view[:own] || view[:own_result] || {}
      participating = !viewer.nil? && (view[:participants] || view[:seats] || []).include?(viewer)
      done = view[:finished] || own[:done] || own[:finished] || own[:phase] == :finished ||
        (view[:answered] && view[:answered][viewer])
      turn = current_turn(view)
      return phase_status(view, participating, done, turn, viewer) if %w[dice_duel risky_dice blackjack numbered_balls sound_memory hit_duck].include?(kind)
      status(kind, view, own, participating, done, turn, viewer, playback_prompts: false)
    end

    def attempts_left(count)
      n_('%{count} attempt left.', '%{count} attempts left.', count) % {count: count}
    end

    def card_rank(rank)
      {1 => _('Ace'), 11 => _('Jack'), 12 => _('Queen'), 13 => _('King')}.fetch(rank, rank.to_s)
    end

    def text(value)
      GameRoomContent.utf8(value.to_s)
    end
  end
end
