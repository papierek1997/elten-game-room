# frozen_string_literal: true
require_relative '../base'
require_relative 'table_round'
require_relative 'tile_labels'
require_relative 'score_breakdown'

module GameRoomGames
  using GameRoomLocalization::Translations

  module MahjongTablePresentation
    include MahjongScoreBreakdown
    def table_surface_spec(round, players:, viewer:)
      unless players.is_a?(Array) && players.length == round.flow.hands.length
        raise ArgumentError, 'Mahjong presentation roster mismatch'
      end
      flow = round.flow
      own = players.index { |player| same_user?(player, viewer) }
      parts = []
      if round.finished?
        text = round.result && !round.result.draw? ? _('Winner: %{player}') % {player: participant_name(players.fetch(round.result.winner))} : _('The hand ended in a draw.')
        parts << mahjong_table_part('status', mahjong_table_info('mahjong-table-status', _('Mahjong'), text))
      else
        text = flow.phase == :kong_reactions ? _('Waiting for claims on a kong: %{tile}.') % {tile: GameRoomMahjong::TileLabels.label(round.added_kong_kind * 4)} : flow.phase == :reactions ? _('Waiting for claims on %{tile}.') % {tile: GameRoomMahjong::TileLabels.label(flow.discards.last.last)} :
          _('%{player} is taking a turn.') % {player: participant_name(players.fetch(flow.seat))}
        parts << mahjong_table_part('status', mahjong_table_info('mahjong-table-status', _('Mahjong'), text))
      end
      parts.concat(mahjong_result_parts(round, players))
      parts.concat(mahjong_hand_parts(round, own))
      parts.concat(mahjong_action_parts(round, own, text))
      parts.concat(mahjong_public_parts(round, players))
      GameSurfaces::CompositeSpec.new(parts: mahjong_order_table_parts(parts))
    end

    private

    def mahjong_result_parts(round, players)
      flow, parts = round.flow, []
      if round.result
        settlement = round.result
        unless settlement.draw?
          winner_tiles = flow.hands[settlement.winner].dup
          winner_tiles << settlement.winning_tile if settlement.discarder
          text = winner_tiles.sort.map { |tile| GameRoomMahjong::TileLabels.label(tile) }.join(', ')
          parts << mahjong_table_part('winning_hand', mahjong_table_info('mahjong-winning-hand', _('Winning hand'), text))
          score = settlement.score
          value = if round.variant == 'mcr'
            _('%{fan} fan; flower points: %{flowers}') % {fan: score.fan, flowers: score.flowers}
          elsif round.variant == 'hong_kong'
            _('%{fan} fan') % {fan: score.fan}
          elsif score.yakuman.positive?
            _('%{count} yakuman') % {count: score.yakuman}
          else
            _('%{han} han, %{fu} fu') % {han: score.han, fu: score.fu}
          end
          breakdown = mahjong_score_breakdown(round)
          value = round.variant == 'mcr' ? breakdown : value + "\n" + breakdown
          parts << mahjong_table_part('value', mahjong_table_info('mahjong-hand-value', _('Hand value'), value))
        end
        payments = settlement.payments.each_with_index.map do |points, seat|
          _('%{player}: %{points}') % {player: participant_full_name(players.fetch(seat)), points: points}
        end
        parts << mahjong_table_part('payments', mahjong_table_info('mahjong-payments', _('Point changes'), payments.join("\n")))
      end
      parts
    end

    def mahjong_hand_parts(round, own)
      flow, parts = round.flow, []
      if own
        discarding = !round.finished? && flow.phase == :discard && flow.seat == own
        if discarding && !round.blocked_discards.empty?
          all_tiles = flow.hands[own].sort.map do |tile|
            GameSurfaces::QuestionOption.new(id: tile.to_s, value: tile.to_s,
              label: GameRoomMahjong::TileLabels.label(tile))
          end
          parts << mahjong_table_part('all_tiles', GameSurfaces::QuestionSpec.new(id: 'mahjong-all-tiles',
            prompt: GameRoomContent.utf8(_('Your tiles')), mode: :single_choice, options: all_tiles, read_only: true))
        end
        hand_tiles = discarding ? round.legal_discards : flow.hands[own]
        choices = hand_tiles.sort_by { |tile| [GameRoomMahjong::Tiles.kind(tile), tile] }.map do |tile|
          label = GameRoomMahjong::TileLabels.label(tile)
          label = _('%{tile} (just drawn)') % {tile: label} if flow.last_draw == tile && flow.seat == own
          GameSurfaces::QuestionOption.new(id: tile.to_s, value: tile.to_s, label: GameRoomContent.utf8(label))
        end
        parts << mahjong_table_part('hand', GameSurfaces::QuestionSpec.new(id: "mahjong-discard:#{flow.generation}",
          prompt: GameRoomContent.utf8(discarding ? _('Tiles available to discard: choose with arrows and press Enter') : _('Your tiles')),
          mode: :single_choice, options: choices, read_only: !discarding, submit_on_select: discarding))
      end
      parts
    end

    def mahjong_action_parts(round, own, text)
      flow, parts = round.flow, []
      if !round.finished? && own
        if %i[reactions kong_reactions].include?(flow.phase) && round.window&.pending&.include?(own)
          options = round.window.offers.fetch(own).map do |choice|
            GameSurfaces::QuestionOption.new(id: choice.join(':'), value: choice.join(':'), label: mahjong_claim_label(choice))
          end
          parts << mahjong_table_part('claims', GameSurfaces::QuestionSpec.new(id: "mahjong-claim:#{flow.generation}",
            prompt: GameRoomContent.utf8("#{text} #{_('Choose a response to the discard')}"), mode: :single_choice,
            options: options, submit_on_select: true))
        elsif flow.seat == own
          commands = []
          if %i[draw replacement].include?(flow.phase)
            commands << GameSurfaces::Command.new(id: flow.phase.to_s,
              label: GameRoomContent.utf8(flow.phase == :draw ? _('Draw a tile') : _('Draw a replacement tile')),
              payload: {'generation'=>flow.generation})
          elsif flow.phase == :discard && flow.last_draw && round.winning_result(own)
            commands << GameSurfaces::Command.new(id: 'win', label: GameRoomContent.utf8(_('Declare Mahjong')),
              payload: {'generation'=>flow.generation})
          end
          parts << mahjong_table_part('commands', GameSurfaces::CommandPanelSpec.new(commands: commands)) unless commands.empty?
          concealed_kongs = round.concealed_kongs
          unless concealed_kongs.empty?
            choices = concealed_kongs.map do |kind|
              GameSurfaces::QuestionOption.new(id: kind.to_s, value: kind.to_s,
                label: GameRoomMahjong::TileLabels.label(kind * 4))
            end
            parts << mahjong_table_part('concealed_kongs', GameSurfaces::QuestionSpec.new(id: "mahjong-kong:#{flow.generation}",
              prompt: GameRoomContent.utf8(_('Choose a concealed kong')), mode: :single_choice,
              options: choices, submit_on_select: true))
          end
          added_kongs = round.added_kongs
          unless added_kongs.empty?
            choices = added_kongs.map do |kind|
              GameSurfaces::QuestionOption.new(id: kind.to_s, value: kind.to_s,
                label: GameRoomMahjong::TileLabels.label(kind * 4))
            end
            parts << mahjong_table_part('added_kongs', GameSurfaces::QuestionSpec.new(id: "mahjong-added-kong:#{flow.generation}",
              prompt: GameRoomContent.utf8(_('Choose a pung to upgrade to a kong')), mode: :single_choice,
              options: choices, submit_on_select: true))
          end
          riichi_discards = round.riichi_discards
          unless riichi_discards.empty?
            choices = riichi_discards.map do |tile|
              GameSurfaces::QuestionOption.new(id: tile.to_s, value: tile.to_s,
                label: GameRoomMahjong::TileLabels.label(tile))
            end
            parts << mahjong_table_part('riichi', GameSurfaces::QuestionSpec.new(id: "mahjong-riichi:#{flow.generation}",
              prompt: GameRoomContent.utf8(_('Declare riichi by choosing a tile to discard')), mode: :single_choice,
              options: choices, submit_on_select: true))
          end
        end
      end
      parts
    end

    def mahjong_public_parts(round, players)
      flow, parts = round.flow, []
      public_lines = flow.melds.each_with_index.flat_map do |sets, seat|
        sets.map do |meld|
          _('%{player}: %{tiles}') % {player: participant_name(players.fetch(seat)),
            tiles: meld[:tiles].map { |tile| GameRoomMahjong::TileLabels.label(tile) }.join(', ')}
        end
      end
      unless public_lines.empty?
        parts << mahjong_table_part('melds', mahjong_table_info('mahjong-melds', _('Exposed sets'), public_lines.join("\n")))
      end
      bonus_lines = flow.flowers.each_with_index.filter_map do |tiles, seat|
        next if tiles.empty?
        _('%{player}: %{tiles}') % {player: participant_name(players.fetch(seat)),
          tiles: tiles.map { |tile| GameRoomMahjong::TileLabels.label(tile) }.join(', ')}
      end
      unless bonus_lines.empty?
        parts << mahjong_table_part('flowers', mahjong_table_info('mahjong-flowers', _('Flowers and seasons'), bonus_lines.join("\n")))
      end
      unless flow.discard_history.empty?
        claimed = flow.melds.flatten(1).flat_map { |meld| meld[:tiles] }
        lines = flow.discard_history.map do |seat, tile|
          label = GameRoomMahjong::TileLabels.label(tile)
          label = _('%{tile} (claimed)') % {tile: label} if claimed.include?(tile)
          _('%{player}: %{tiles}') % {player: participant_name(players.fetch(seat)), tiles: label}
        end
        parts << mahjong_table_part('discards', mahjong_table_info('mahjong-discards', _('Discards'), lines.join("\n")))
      end
      parts << mahjong_table_part('wall', mahjong_table_info('mahjong-wall', _('Wall'), _('Tiles left: %{count}.') % {count: flow.wall.length}))
      unless flow.dora_indicators.empty?
        labels = flow.dora_indicators.map { |tile| GameRoomMahjong::TileLabels.label(tile) }.join(', ')
        parts << mahjong_table_part('dora', mahjong_table_info('mahjong-dora', _('Dora indicators'), labels))
      end
      if round.riichi_state && round.riichi_state.levels.any?(&:positive?)
        lines = round.riichi_state.levels.each_with_index.filter_map do |level, seat|
          next if level.zero?
          text = level == 2 ? _('%{player}: double riichi') : _('%{player}: riichi')
          text % {player: participant_name(players.fetch(seat))}
        end
        sticks = round.riichi_outcome ? round.riichi_outcome.sticks : round.riichi_state.sticks
        lines << _('Deposits on the table: %{count}.') % {count: sticks}
        parts << mahjong_table_part('riichi_status', mahjong_table_info('mahjong-riichi-status', _('Riichi declarations'), lines.join("\n")))
      end
      parts
    end

    def mahjong_order_table_parts(parts)
      actions = parts.select { |part| %w[claims commands concealed_kongs added_kongs riichi match_ready].include?(part.id) }
      [parts.first, *actions, *parts.drop(1).reject { |part| actions.include?(part) }]
    end

    def mahjong_claim_label(choice)
      label = case choice.first
      when :pass then _('Pass')
      when :win then _('Declare Mahjong')
      when :chow then _('Chow')
      when :pung then _('Pung')
      when :kong then _('Kong')
      else raise ArgumentError, 'Unknown mahjong claim label'
      end
      if choice.first == :chow
        tiles = GameRoomMahjong::Hand.tiles_for(choice).map { |kind| GameRoomMahjong::TileLabels.label(kind * 4) }.join(', ')
        label = _('%{action}: %{tiles}') % {action: label, tiles: tiles}
      end
      GameRoomContent.utf8(label)
    end

    def mahjong_table_part(id, surface)
      GameSurfaces::SurfacePart.new(id: id, surface: surface)
    end

    def mahjong_table_info(id, title, text)
      GameSurfaces::QuestionSpec.new(id: id, prompt: GameRoomContent.utf8(title), mode: :information,
        value: GameRoomContent.utf8(text), read_only: true)
    end
  end
end
