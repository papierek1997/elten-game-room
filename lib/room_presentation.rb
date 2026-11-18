require_relative "game_participants"

require_relative "game_room_localization"

module RoomPresentation
  using GameRoomLocalization::Translations
  User = Struct.new(:participant, :label, keyword_init: true) do
    def to_s
      label
    end
  end

  module_function

  def user_labels(members, **options)
    user_rows(members, **options).map(&:label)
  end

  def user_rows(members, bots: [], observers: [], owner:, players:, active:, team_assignment: nil, statuses: {}, scores: nil, names: nil)
    participants = GameRoomParticipants.unique(members.to_a + bots.to_a + players.to_a)
    participants.map do |participant|
      roles = []
      roles << _("table master") if GameRoomParticipants.human?(participant) && same_user?(participant, owner)
      roles << _("computer") if GameRoomParticipants.bot?(participant)
      observes_next = includes_user?(observers, participant)
      if active
        current_player = includes_user?(players, participant)
        roles << (current_player ? _("player") : _("observer"))
        roles << _("will observe the next game") if current_player && observes_next
        roles << _("will play in the next game") if !current_player && !observes_next && GameRoomParticipants.human?(participant)
      else
        roles << (observes_next ? _("observer") : _("waiting for a game"))
      end
      team = team_assignment&.team_number_for(participant)
      roles << _("team %{team}") % { team: team } if team != nil
      status = participant_status(statuses, participant)
      roles << status if !status.to_s.empty?
      score = scores&.find { |player, _points| same_user?(player, participant) }
      roles << (_("%{points} points") % { points: score[1] }) if score != nil && score[1] != nil
      User.new(participant: participant, label: _("%{user}, %{roles}") % {
        user: names ? names.format(participant, form: :full) : GameRoomParticipants.display_name(participant),
        roles: roles.join(", ")
      })
    end
  end

  def game_users(room:, game:, replay:, players:, owner:, options: {}, controllers: {}, names: nil)
    players = players.to_a
    active = replay != nil && !replay.finished?
    # Finished results annotate people still at the table. Departed players
    # remain in the game's replay, but are not manageable room members.
    listed_players = active ? players : []
    statuses = listed_players.each_with_object({}) do |participant, result|
      result[participant] = game.participant_status(
        replay, participant,
        connected: GameRoomParticipants.bot?(participant) || includes_user?(room.members, participant)
      )
    end
    user_rows(
      room.members, bots: room.bots.to_a, observers: room.observers.to_a, owner: owner,
      players: listed_players, active: active,
      team_assignment: active ? game.team_assignment(options, players: players) : game&.prepared_team_assignment(options, players: room.game_participants),
      statuses: statuses, scores: replay == nil ? nil : game.participant_scores(replay), names: names
    )
  end

  def includes_user?(users, user)
    users.to_a.any? { |candidate| same_user?(candidate, user) }
  end

  def same_user?(first, second)
    GameRoomParticipants.same?(first, second)
  end

  def participant_status(statuses, participant)
    return nil if !statuses.respond_to?(:each)

    pair = statuses.find { |candidate, _value| same_user?(candidate, participant) }
    pair == nil ? nil : pair[1].to_s
  end
end
