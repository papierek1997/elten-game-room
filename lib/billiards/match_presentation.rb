require_relative 'presentation'
require_relative 'rules'

module GameRoomBilliards
  module MatchPresentation
    using GameRoomLocalization::Translations
    module_function

    def choice(id, decision = nil)
      case id
      when 'accept' then decision == :respotted_black ? _('Play the respotted black') : _('Play from the current position')
      when 'return' then _('Ask the opponent to play from the current position')
      when 'restore' then _('Restore the position and ask the offender to play again')
      when 'hand' then _('Take the cue ball in hand behind the head string')
      when 'rack_self' then _('Rerack and break yourself')
      when 'rack_other' then _('Rerack and let the opponent break')
      when 'next' then _('Start the next rack or frame')
      when 'agree' then _('Agree to rerack without awarding a point')
      when 'decline' then _('Keep playing the current rack or frame')
      when 'pocket_2' then Presentation.pocket(2)
      when 'pocket_5' then Presentation.pocket(5)
      when 'english_accept' then _('Play from the current position')
      when 'english_reset' then _('Reset the English billiards balls and play from the D')
      when 'carom_start_left' then _('Start from the lower opening spot')
      when 'carom_start_right' then _('Start from the upper opening spot')
      when 'carom_play_away' then _('Play away from the touching ball')
      when 'carom_respot' then _('Respot the touching balls')
      when 'pyramid_accept' then _('Play from the current position')
      when 'pyramid_return' then _('Ask the opponent to play from the current position')
      when 'pyramid_rack_self' then _('Rerack and break yourself')
      when 'pyramid_rack_other' then _('Rerack and let the opponent break')
      else
        if /\Apyramid_penalty_(\d+)\z/.match?(id)
          _('Take %{ball} as the penalty point') % {ball: Presentation.ball(id.split('_').last.to_i, discipline: 'pyramid')}
        else
          raise ArgumentError, "Unknown billiards decision: #{id}"
        end
      end
    end

    def ruling(state)
      ruling = state[:ruling]
      foul = {scratch: _('Cue ball pocketed.'), wrong_first: _('Wrong ball first.'), no_contact: _('No object ball was hit.'),
        no_rail: _('No cushion contact after the object ball.'), break_spread: _('Not enough balls reached cushions on the break.'),
        three_ball_break: _('The break did not satisfy the three-ball rule.'), early_eight: _('The 8-ball was pocketed incorrectly.'),
        wrong_pot: _('A ball that was not on was pocketed.'), push: _('Push stroke.'), free_ball_snooker: _('The free ball snookered the opponent.'),
        head_string: _('Illegal direct contact behind the head string.'),
        early_final: _('The final ball was pocketed incorrectly.'),
        third_miss: _('Third miss from the restored open position: frame lost.'),
        off_table: _('A ball left the table.'), head_string_hand: _('The cue ball failed to leave the head area.'),
        two_fouls: _('Two consecutive fouls: another foul carries the discipline\'s three-foul penalty.'),
        straight_break: _('The opening break did not meet the cushion requirement.'),
        straight_three: _('Three consecutive fouls: an additional fifteen-point penalty and a new opening break.'),
        three_fouls: _('Three consecutive fouls: an additional fifteen-point penalty and a new opening break.'),
        straight_rerack: _('Fourteen balls reracked; continue the current visit.'),
        black_break: _('Black pocketed on the break: the same player breaks again.'),
        opening_contact: _('The opening shot must hit the red directly.'),
        frozen_cushion: _('The cue was played into a touching cushion.'),
        insufficient_cushions: _('Not enough cushion contacts before the second object ball.'),
        zone_limit: _('An object ball had to leave the restricted corner zone.'),
        equalizing_inning: _('The opponent has an equalizing inning.'),
        baulk_play: _('Illegal play from the D into baulk.'), running_coup: _('The cue ball entered a pocket without hitting an object ball.'),
        cannon_limit: _('The limit of consecutive cannons was exceeded.'), hazard_limit: _('The limit of consecutive hazard strokes was exceeded.'),
        baulk_crossing: _('The required baulk crossing was not completed.'),
        english_miss: _('Miss: two points to the opponent.'), seventy_cannons: _('Seventy consecutive cannons: the limit is seventy-five.'),
        ten_hazards: _('Ten consecutive hazard strokes: the limit is fifteen.'), time: _('Time is up.'),
        pyramid_completion: _('The shot did not satisfy the pyramid continuation rule.')}
      parts = []
      parts << foul.fetch(ruling[:notice]) if ruling[:notice]
      parts << _('Foul: %{reason}') % {reason: foul.fetch(ruling[:foul])} if ruling[:foul]
      if ruling[:points].to_i > 0
        parts << (ruling[:foul] || ruling[:notice] == :english_miss ? _('Penalty points to the opponent: %{points}.') : _('Points scored: %{points}.')) % {points: ruling[:points]}
      elsif ruling[:points].to_i < 0
        parts << _('Point penalty: %{points}.') % {points: -ruling[:points]}
      end
      parts << _('Foul and a Miss.') if ruling[:miss]
      parts << _('Two consecutive fouls: another foul carries the discipline\'s three-foul penalty.') if state[:fouls]&.include?(2) && ruling[:notice] != :two_fouls
      parts << _('Warning: another miss from this restored open position loses the frame.') if state[:miss_chain] == 2
      parts << _('Free ball available.') if state[:free_ball]
      parts << _('P: choose the decision.') unless state[:choices].empty?
      GameRoomContent.utf8(parts.join(' '))
    end

    def next_stroke(state)
      return '' unless state[:phase] == :playing && state[:choices].empty?
      parts = []
      if Rules.snooker?(state)
        label = case state[:on]
        when :red then _('Red')
        when :colour then _('Choose a colour')
        else Presentation.ball(state[:on], discipline: 'snooker')
        end
        parts << _('Ball on: %{balls}.') % {balls: label}
      end
      unless state[:balls].find { |b| b.id == Rules.cue_id(state) }&.on_table?
        parts << _('M: place the cue ball.')
      end
      GameRoomContent.utf8(parts.join(' '))
    end

    def status(state)
      discipline = state[:options]['discipline']
      title = {'eight'=>_('Pool: 8-ball'), 'nine'=>_('Pool: 9-ball'), 'snooker'=>_('Snooker: 15 reds'), 'friendly'=>_('Social billiards'),
        'ten'=>_('Pool: 10-ball'), 'straight'=>_('Pool: 14.1 continuous'), 'one_pocket'=>_('Pool: One Pocket'),
        'bank_short'=>_('Bank Pool: 9 balls'), 'bank_full'=>_('Bank Pool: 15 balls'), 'cutthroat'=>_('Cutthroat: three players'),
        'blackball'=>_('Blackball'), 'english'=>_('English Billiards'), 'carom'=>_('Carom: straight rail'),
        'one_cushion'=>_('Carom: one cushion'), 'three_cushion'=>_('Carom: three cushions'), 'pyramid'=>_('Free Pyramid')}.fetch(discipline)
      parts = [title, _('Racks or frames: %{score}.') % {score: state[:racks].join(':')}]
      parts << _('Points: %{score}.') % {score: state[:scores].join(':')} if Rules.points_game?(state)
      parts << _('Cue ball: %{ball}.') % {ball: Presentation.ball(Rules.cue_id(state), discipline: discipline)}
      parts << _('Final ball: %{ball}.') % {ball: Presentation.ball(state[:final_ball])} if state[:final_ball]
      if state[:phase] == :playing
        on = Rules.targets(state)
        labels = if Rules.snooker?(state) && state[:on] == :red then _('Red')
        elsif Rules.snooker?(state) && state[:on] == :colour then _('Choose a colour')
        else on.map { |id| Presentation.ball(id, discipline: discipline) }.join('; ')
        end
        parts << _('Ball on: %{balls}.') % {balls: labels}
        hand = {d: _('Cue ball in hand in the D.'), kitchen: _('Cue ball in hand behind the head string.'), any: _('Cue ball in hand anywhere.'), baulk: _('Cue ball in hand in baulk.')}
        parts << hand.fetch(state[:hand]) if state[:hand]
        parts << _('Break shot.') if state[:breaking]
        parts << _('Push-out available.') if state[:push_available]
        parts << _('Free shot available; M optionally moves the cue ball into baulk.') if state[:blackball_free]
        if state[:groups] && discipline == 'blackball' || state[:groups] && discipline == 'eight'
          parts << _('Your group: %{group}.') % {group: state[:groups][state[:turn]].zero? ? _('solid balls') : _('striped balls')}
        end
        if state[:point_pockets] && state[:point_pockets][state[:turn]]
          parts << _('Your scoring pocket: %{pocket}.') % {pocket: Presentation.pocket(state[:point_pockets][state[:turn]])}
        end
        parts << _('Current break: %{points}.') % {points: state[:break_points]} if Rules.snooker?(state)
      end
      parts << ruling(state)
      GameRoomContent.utf8(parts.reject(&:empty?).join(' '))
    end
  end
end
