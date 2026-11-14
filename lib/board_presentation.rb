require_relative "game_room_localization"

module GameRoomBoardPresentation
  using GameRoomLocalization::Translations
  def board_owner_label(replay, marker)
    marker == nil ? "" : participant_name(replay.players[marker])
  end

  def board_move_text(actor, field)
    _("%{player} %{field}.") % { player: participant_name(actor), field: field }
  end

  def describe_event(event, repository, replay, _viewer)
    entry = replay.history.find do |candidate|
      candidate.kind == :move && candidate.event_id.to_i == repository.event_id(event).to_i
    end
    entry&.text
  end
end
