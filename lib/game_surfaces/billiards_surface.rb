require_relative 'specifications'
require_relative '../billiards/presentation'
require_relative '../billiards/controls'
require_relative '../billiards/aim_audio'
require_relative '../billiards/match_presentation'

module GameSurfaces
  using GameRoomLocalization::Translations

  class BilliardsField < Button
    attr_accessor :adjustment, :readout, :aim_audio

    def update
      super
      GameRoomBilliards::Controls.adjustments.each do |key, modifiers, parameter, delta, _|
        next unless key_pressed?("key_#{key}".to_sym, repeat: true)
        next unless GameRoomUI.modifiers_when_pressed(self, key, include_insert: true) == modifiers
        @pending_readout = parameter if @adjustment.call(parameter, delta)
      end
      # Holding an arrow changes the draft, but only its final value is spoken.
      if @pending_readout && [0x25, 0x26, 0x27, 0x28].none? { |code| key_held?(code) }
        @readout.call(@pending_readout)
        @pending_readout = nil
      end
    end

    def blur
      @pending_readout = nil
      @aim_audio&.stop
      super if defined?(super)
    end

    def key_processed(key)
      return true if %w[left right up down].include?(key.to_s.sub(/\Akey_/, ''))
      super
    end
  end

  class BilliardsSurface
    include ActionEmitter
    B = GameRoomBilliards
    attr_reader :spec

    def initialize(spec, state: {})
      @spec, @table = spec, B::Rules.table(spec.options)
      @competition = B::Rules.competition?(spec.options)
      @cue_id = @competition ? B::Rules.cue_id(spec.rules.merge(options: spec.options)) : 0
      state = {} unless state_value(state, 'game_id', nil) == spec.game_id
      saved = state_value(state, 'shot', nil)
      @shot = B::Physics.valid_shot?(saved) ? saved.dup : {'angle'=>0, 'power'=>350, 'top'=>0, 'side'=>0}
      @selected = state_value(state, 'selected', 1)
      @pocket = state_value(state, 'pocket', 5).to_i.clamp(0, 5)
      @clock = state_value(state, 'clock', false) == true
      @call = state_value(state, 'call', nil) if state_value(state, 'declaration_epoch', nil) == spec.epoch
      @mode = @call ? state_value(state, 'mode', 0) : 0
      @rails = @call ? state_value(state, 'rails', []) : []
      saved_cue = state_value(state, 'cue', @cue_id)
      @cue_id = saved_cue if @table.discipline == 'pyramid' && !@spec.rules[:breaking] && @spec.balls.any? { |b| b.id == saved_cue && b.on_table? }
      @field = BilliardsField.new(text(_('Cue: aim with the arrows; Enter or Space plays the shot.')))
      @field.adjustment = method(:adjust)
      @field.readout = ->(parameter) do
        if parameter == 'angle'
          contact = shot_line
          say(B::Presentation.target(contact, discipline: @table.discipline)) unless contact && contact[:kind] == :pocket
        else
          handle_command(parameter)
        end
      end
      @field.on(:press) do
        modified = [:enter, :space].any? do |key|
          @field.__send__(:key_pressed?, "key_#{key}".to_sym) &&
            !GameRoomUI.modifiers_when_pressed(@field, key, include_insert: true).empty?
        end
        submit('shot', 'shot'=>@shot.dup) unless modified
      end
      GameRoomContextHelp.replace([@field], B::Controls.adjustments.map(&:last) +
        [_('Enter or Space: play the current shot.')])
      @balls = RefreshAwareListBox.new(ball_labels, header: text(_('Balls on the table')), quiet: true)
      @balls.on(:move) { @selected = @ball_ids[@balls.index] }
      @balls.on(:select) { handle_command('selected') }
      @balls.index = @ball_ids.index(@selected) || 0
      if @competition
        @match_button = Button.new(text(_('Shot declarations and match decisions')))
        @match_button.on(:press) { match_options }
      end
    end

    def fields; [@field, @balls, @match_button].compact; end
    def attach_form(form)
      @form = form
      @field.aim_audio = @aim_audio ||= B::AimAudio.new(program) if program
    end
    def state
      result = {'game_id'=>@spec.game_id, 'shot'=>@shot.dup, 'selected'=>@selected, 'pocket'=>@pocket, 'clock'=>@clock}
      result.merge!('call'=>@call, 'mode'=>@mode, 'rails'=>@rails.dup, 'cue'=>@cue_id, 'declaration_epoch'=>@spec.epoch) if @competition
      result
    end

    def handle_command(command, _payload = {})
      return false if @competition && %w[undo reset pass finish].include?(command)
      case command
      when 'angle' then say(B::Presentation.direction(@shot['angle'] / 100.0, clock: @clock))
      when 'power' then say(_('%{power} percent power.') % {power: format('%.1f', @shot['power'] / 10.0)})
      when 'line' then say(B::Presentation.target(shot_line, discipline: @table.discipline))
      when 'behind' then say(B::Presentation.behind(B::Geometry.through(@table, @spec.balls, @cue_id, B::Physics.launch_angle(@shot)), discipline: @table.discipline))
      when 'near'
        nearby = B::Geometry.nearby(@table, @spec.balls, @cue_id, B::Physics.launch_angle(@shot))
        say(nearby.empty? ? _('No object balls within 5 degrees of the shot line.') :
          nearby.map { |b| position(b[:id]) }.join("\n"))
      when 'selected' then say(position(@selected))
      when 'overview' then show_text(_('Ball positions'), ball_labels.join("\n"))
      when 'next', 'previous' then cycle_ball(command == 'next' ? 1 : -1)
      when 'pocket' then choose_pocket
      when 'aim', 'pocket_aim' then aim(command == 'pocket_aim')
      when 'parameters' then edit_parameters
      when 'top', 'back', 'left_spin', 'right_spin'
        parameter, delta = {'top'=>['top', 5], 'back'=>['top', -5], 'left_spin'=>['side', -5], 'right_spin'=>['side', 5]}.fetch(command)
        if adjust(parameter, delta)
          say(B::Presentation.parameters(@shot))
        else
          say(_('The combined spin must stay within the cue ball.'))
        end
      when 'neutral'
        @shot['top'] = @shot['side'] = 0
        play_aim_tone
        say(B::Presentation.parameters(@shot))
      when 'clock'
        @clock = !@clock
        handle_command('angle')
      when 'predict' then predict
      when 'rebound' then predict(rebound: true)
      when 'object_prediction' then predict(object: true)
      when 'contacts'
        show_text(_('Last shot'), @spec.last ? B::Presentation.parameters(@spec.last_shot) + "\n" +
          @spec.last.events.map { |e| format('%.2f s: %s', e[:t], B::Presentation.contact(e, discipline: @table.discipline)) }.join("\n") : _('No shot has been played yet.'))
      when 'place' then place_ball
      when 'match_options' then return false unless @competition; match_options
      when 'match_status' then return false unless @competition; say(B::MatchPresentation.status(rule_state))
      when 'concede'
        return false unless @competition
        epoch = @spec.epoch
        selected = choose(_('Concede this rack or frame?'), [_('No'), _('Yes')])
        submit('concede') if selected == 1 && current?(epoch)
      when 'undo'
        @spec.undo ? submit('undo') : say(_('Undo is available after a shot in solo practice.'))
      when 'pass' then submit('pass')
      when 'reset', 'finish'
        epoch = @spec.epoch
        message = command == 'reset' ? _('Restore the original layout?') : _('Finish this practice session?')
        choice = choose(message, [_('No'), _('Yes')])
        submit(command) if choice == 1 && current?(epoch)
      else return false
      end
      true
    end

    private

    def text(value); GameRoomContent.utf8(value); end
    def say(value); speak(text(value)); end
    def shot_line; B::Geometry.trace(@table, @spec.balls, @cue_id, B::Physics.launch_angle(@shot)); end
    def rule_state; @spec.rules.merge(balls: @spec.balls, options: @spec.options, pyramid_cue: @cue_id); end
    def cue_ball; @spec.balls.find { |b| b.id == @cue_id }; end
    def position(id); B::Presentation.position(@table, @spec.balls, id, clock: @clock, cue_id: @cue_id); end
    def play_aim_tone
      contact = shot_line if @spec.enabled && action_allowed?
      @aim_audio&.update(contact)
      pocket = contact[:id] if contact && contact[:kind] == :pocket
      say(_('Pocket %{number}') % {number: pocket + 1}) if pocket && pocket != @last_aim_pocket
      @last_aim_pocket = pocket
    end
    def program; @form&.game_room_program; end
    def current?(epoch)
      @spec.epoch == epoch && action_allowed? && (!@form || @form.fields.include?(@field))
    end
    def submit(action, payload = {})
      @aim_audio&.stop
      return say(_('Wait for your turn.')) unless @spec.enabled
      return unless action_allowed?
      epoch = @spec.epoch
      if action == 'shot'
        if @competition
          return match_options unless @spec.rules[:choices].empty?
          cue = cue_ball
          return say(_('M: place the cue ball.')) if @spec.rules[:hand] && !B::Rules.placement?(rule_state, @cue_id, cue.x, cue.y)
          return unless @call || declare_shot
          payload = payload.merge('call'=>@call, 'mode'=>@mode, 'pocket'=>@pocket)
          payload.merge!('cue'=>@cue_id, 'rails'=>@rails.dup) if B::Rules.advanced?(@spec.options)
        end
        return say(_('Place the cue ball before aiming.')) unless cue_ball&.on_table?
        balls, shot, accurate = @spec.balls.map(&:dup), payload.fetch('shot').dup, @spec.options['accurate']
        cue_id = @cue_id
        EltenAPI::Tasks.run(title: text(_('Predicting the shot')), timeout: 15) do |_progress, token|
          token.raise_if_cancelled!
          B::Physics.simulate(@table, balls, shot, accurate: accurate, cue_id: cue_id)
        end
        return unless current?(epoch)
      end
      emit_action('billiards', action, payload.merge('revision'=>@spec.epoch))
    rescue B::Physics::LimitExceeded, EltenAPI::Tasks::TimedOut
      say(_('This shot could not be simulated. The table has not changed.'))
    rescue EltenAPI::Tasks::Cancelled
      nil
    end
    def adjust(parameter, delta)
      candidate = @shot.dup
      candidate[parameter] += delta
      candidate['angle'] %= 36_000
      candidate['power'] = candidate['power'].clamp(1, 1000)
      return false unless B::Physics.valid_shot?(candidate)
      @shot = candidate
      play_aim_tone if %w[angle side].include?(parameter)
      true
    end
    def ball_labels
      cue = cue_ball
      ordered = @spec.balls.sort_by { |b| [b.on_table? ? 0 : 1, Math.hypot(b.x - cue.x, b.y - cue.y), b.id] }
      @ball_ids = ordered.map(&:id)
      ordered.map { |b| position(b.id) }
    end
    def cycle_ball(delta)
      ids = @spec.balls.select { |b| b.id != @cue_id && b.on_table? }.map(&:id)
      return say(_('No object balls remain on the table.')) if ids.empty?
      @selected = ids[((ids.index(@selected) || (delta.positive? ? -1 : 0)) + delta) % ids.length]
      @balls.index = @ball_ids.index(@selected) || 0
      handle_command('selected')
    end
    def choose(prompt, labels, index: 0)
      @aim_audio&.stop
      GameRoomUI.choose_index(text(prompt), labels, program: program, index: index)
    end
    def choose_pocket
      return say(_('This table has no pockets.')) if @table.pockets.empty?
      epoch = @spec.epoch
      chosen = choose(_('Target pocket'), @table.pockets.each_index.map { |i| B::Presentation.pocket(i) }, index: @pocket)
      @pocket = chosen if chosen && current?(epoch)
    end
    def aim(pocket)
      cue, target = [@cue_id, @selected].map { |id| @spec.balls.find { |b| b.id == id && b.on_table? } }
      return say(_('Select an object ball and place the cue ball first.')) unless cue && target && cue != target
      angle = pocket ? B::Geometry.pocket_aim(@table, @spec.balls, @cue_id, @selected, @pocket) :
        B::Geometry.angle(target.x - cue.x, target.y - cue.y)
      return say(_('That pocket cannot be reached with a direct cut from this side.')) unless angle
      @shot['angle'] = (angle * 100).round % 36_000
      play_aim_tone
      say(B::Presentation.target(shot_line, discipline: @table.discipline))
    end
    def edit_parameters
      epoch = @spec.epoch
      values = number_form(_('Shot parameters'), [
        [_('Angle in degrees (0 to 359.99)'), @shot['angle'] / 100.0, 100, 0..359.99],
        [_('Power in percent (0.1 to 100)'), @shot['power'] / 10.0, 10, 0.1..100],
        [_('Top/back spin (-100 to 100)'), @shot['top'], 1, -100..100],
        [_('Right/left spin (-100 to 100)'), @shot['side'], 1, -100..100]]) do |numbers|
          B::Physics.valid_shot?(%w[angle power top side].zip(numbers).to_h)
        end
      return unless values && current?(epoch)
      @shot = %w[angle power top side].zip(values).to_h
      play_aim_tone
      say(B::Presentation.parameters(@shot))
    end
    def place_ball
      return say(_('Wait for your turn.')) unless @spec.enabled
      epoch = @spec.epoch
      if @competition
        return say(_('The cue ball is not in hand.')) unless (@spec.rules[:hand] || @spec.rules[:blackball_free]) && @spec.rules[:choices].empty?
        id = @cue_id
      else
        ids = @spec.balls.map(&:id)
        index = choose(_('Ball to place'), ids.map { |id| B::Presentation.ball(id) }, index: ids.index(@selected) || 0)
        return unless index && current?(epoch)
        id = ids.fetch(index)
      end
      ball = @spec.balls.find { |b| b.id == id }
      min = (@table.radius * 100).ceil(2)
      max_x, max_y = ((@table.width - @table.radius) * 100).floor(2), ((@table.height - @table.radius) * 100).floor(2)
      x, y = ball.on_table? ? [ball.x, ball.y] : [%w[snooker english].include?(@table.discipline) ? 0.55 : @table.baulk_line - 0.1, @table.height / 2]
      values = number_form(_('Ball position'), [
        [_('X in centimetres from the left cushion'), (x * 100).round(2).clamp(min, max_x), 100, min..max_x],
        [_('Y in centimetres from the bottom cushion'), (y * 100).round(2).clamp(min, max_y), 100, min..max_y]]) do |numbers|
          if @competition
            B::Rules.placement?(rule_state, id, numbers[0] / 10_000.0, numbers[1] / 10_000.0)
          else
            @table.placement?(@spec.balls, id, numbers[0] / 10_000.0, numbers[1] / 10_000.0)
          end
        end
      submit('place', 'ball'=>id, 'x'=>values[0], 'y'=>values[1]) if values && current?(epoch)
    end
    def match_options
      return say(B::MatchPresentation.status(rule_state)) unless @spec.enabled
      epoch = @spec.epoch
      choices = @spec.rules[:choices]
      if choices.empty?
        options = [_('Declare the next shot'), _('Propose a stalemate rerack')]
        options << _('Spot the nearest legal ball outside the head area') if B::Rules.head_spot(rule_state)
        options << _('Choose the cue ball') if @table.discipline == 'pyramid' && !@spec.rules[:breaking]
        selected = choose(_('Match options'), options)
        return unless selected && current?(epoch)
        case options.fetch(selected)
        when _('Declare the next shot') then declare_shot(explicit: true)
        when _('Propose a stalemate rerack') then submit('stalemate')
        when _('Spot the nearest legal ball outside the head area') then submit('head_spot')
        when _('Choose the cue ball') then choose_cue
        end
      else
        selected = choose(_('Match decision'), choices.map { |id| B::MatchPresentation.choice(id, @spec.rules[:decision]) })
        submit('choice', 'choice'=>selected) if selected && current?(epoch)
      end
    end

    def declare_shot(explicit: false)
      epoch, state = @spec.epoch, rule_state
      return false unless @spec.enabled && current?(epoch) && state[:choices].empty?
      implementation = B::Rules.engine(@spec.options)
      if implementation && !implementation.uses_calls?
        @call, @mode = 0, 0
        say(B::MatchPresentation.status(state)) if explicit
        return true
      end
      if @table.discipline != 'snooker' && state[:breaking] && !B::Rules.calls_break?(@spec.options)
        @call, @mode = 0, 0
        say(B::MatchPresentation.status(state)) if explicit
        return true
      end
      if @table.discipline == 'nine'
        modes = state[:push_available] && explicit ? [_('Normal shot'), _('Push-out')] : nil
        selected = modes ? choose(_('Shot type'), modes) : 0
        return false unless selected && current?(epoch)
        @call, @mode = 0, selected == 1 ? 2 : 0
      else
        snooker = @table.discipline == 'snooker'
        ten = @table.discipline == 'ten'
        types = if snooker then state[:free_ball] ? [_('Normal shot'), _('Nominate a free ball')] : nil
        elsif ten then state[:push_available] && explicit ? [_('Called shot'), _('Push-out')] : nil
        else [_('Called shot'), _('Safety')]
        end
        kind = types ? choose(_('Shot type'), types) : 0
        return false unless kind && current?(epoch)
        if !snooker && kind == 1
          @call, @mode, @rails = 0, ten ? 2 : 1, []
        else
          on = snooker ? B::Rules.snooker_targets(state) : B::Rules.pool_targets(state)
          free = snooker && kind == 1
          ids = free ? @spec.balls.select { |b| b.id != 0 && b.on_table? && !on.include?(b.id) }.map(&:id) : on
          need_choice = !snooker || free || state[:on] == :colour || explicit
          chosen = need_choice ? choose(_('Ball to declare'), ids.map { |id| B::Presentation.ball(id, discipline: @table.discipline) }, index: ids.index(@selected) || 0) : 0
          return false unless chosen && current?(epoch)
          ball = ids.fetch(chosen)
          pocket = snooker ? @pocket : choose(_('Target pocket'), @table.pockets.each_index.map { |i| B::Presentation.pocket(i) }, index: @pocket)
          return false unless pocket && current?(epoch)
          rails = %w[bank_short bank_full].include?(@table.discipline) ? choose_rails(epoch) : []
          return false unless rails && current?(epoch)
          @call, @mode, @pocket = ball, free ? 3 : 0, pocket
          @rails = rails
          say(snooker ? B::Presentation.ball(@call, discipline: @table.discipline) :
            _('Declared: %{ball}; %{pocket}.') % {ball: B::Presentation.ball(@call), pocket: B::Presentation.pocket(@pocket)})
        end
      end
      true
    end

    def choose_cue
      epoch = @spec.epoch
      ids = @spec.balls.select(&:on_table?).map(&:id)
      chosen = choose(_('Choose the cue ball'), ids.map { |id| B::Presentation.ball(id, discipline: @table.discipline) }, index: ids.index(@cue_id) || 0)
      return unless chosen && current?(epoch)
      @cue_id, @call, @rails = ids.fetch(chosen), nil, []
      play_aim_tone
      say(_('Cue ball: %{ball}.') % {ball: B::Presentation.ball(@cue_id, discipline: @table.discipline)})
    end

    def choose_rails(epoch)
      rails = []
      loop do
        labels = [:left, :right, :top, :bottom].map { |side| B::Presentation.rail(side) } + [_('Finish cushion route')]
        chosen = choose(_('Next cushion in the called route'), labels)
        return nil unless chosen && current?(epoch)
        return rails unless chosen != 4 || rails.empty?
        if rails.length < 12 && chosen != 4
          rails << chosen
          say(rails.map { |side| labels[side] }.join('; '))
        else
          say(_('Declare from 1 to 12 cushion contacts, then finish the route.'))
        end
      end
    end
    def number_form(title, definitions)
      @aim_audio&.stop
      edits = definitions.map { |label, value, _scale, _range| EditBox.new(text(label), type: 0, text: value.to_s, quiet: true) }
      accept, cancel = Button.new(text(_('Apply'))), Button.new(text(_('Cancel')))
      form = GameRoomUI::Form.new(edits + [accept, cancel], program: program, quiet: true)
      form.accept_button, form.cancel_button = accept, cancel
      result = nil
      accept.on(:press) do
        numbers = definitions.each_with_index.map { |(_, _, scale, range), i| B::Controls.decimal(edits[i].text, scale: scale, range: range) }
        if numbers.none?(&:nil?) && yield(numbers)
          result = numbers
          form.resume
        else
          say(_('Check the numbers and allowed ranges. Balls must not overlap; combined spin must fit within the cue ball.'))
        end
      end
      cancel.on(:press) { form.resume }
      say(title)
      form.wait
      result
    ensure
      EltenAPI::KeyboardState.clear_current_frame if form
    end
    def predict(rebound: false, object: false)
      @aim_audio&.stop
      return say(_('Place the cue ball before aiming.')) unless cue_ball&.on_table?
      return say(_('Aim at a cushion before asking for a rebound prediction.')) if rebound && shot_line&.dig(:kind) != :rail
      target = shot_line if object
      return say(_('Aim at an object ball before predicting its movement.')) if object && target&.dig(:kind) != :ball
      epoch, balls, shot, accurate = @spec.epoch, @spec.balls.map(&:dup), @shot.dup, @spec.options['accurate']
      cue_id = @cue_id
      result = EltenAPI::Tasks.run(title: text(_('Predicting the shot')), timeout: 15) do |_progress, token|
        token.raise_if_cancelled!
        B::Physics.simulate(@table, balls, shot, accurate: accurate, cue_id: cue_id)
      end
      return unless result && current?(epoch)
      return say(B::Presentation.object_prediction(result, target[:id], discipline: @table.discipline)) if object
      return say(B::Presentation.rebound(result, discipline: @table.discipline, cue_id: @cue_id)) if rebound
      show_text(_('Shot prediction'), B::Presentation.summary(result, discipline: @table.discipline) + "\n" +
        result.balls.map { |b| B::Presentation.position(@table, result.balls, b.id, clock: @clock, cue_id: @cue_id) }.join("\n"))
    rescue B::Physics::LimitExceeded
      say(_('This shot could not be simulated. The table has not changed.'))
    rescue EltenAPI::Tasks::Cancelled
      nil
    rescue EltenAPI::Tasks::TimedOut
      say(_('Shot prediction took too long. The table has not changed.'))
    end
    def show_text(title, value)
      @aim_audio&.stop
      field = GameRoomUI::HelpText.new(text(title), type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
        text: text(value), quiet: true)
      close = Button.new(text(_('Close')))
      form = GameRoomUI::Form.new([field, close], program: program, quiet: true)
      form.accept_button = form.cancel_button = close
      close.on(:press) { form.resume }
      form.wait
    ensure
      EltenAPI::KeyboardState.clear_current_frame if form
    end
  end
end
