require_relative 'game_participants'

# Shared round-completion feedback and tile-game cue projection.
module GameRoomRoundCues
  COMPLETION_CUES = %w[win1 win2 lose1 lose3 win_party lose_party poker_pot
    tysiac_contract_made tysiac_contract_failed tysiac_surrender typing_endgame ding round_finished].freeze
  module_function

  def missing_completion_cue(game:, before_replay:, after_replay:, history:, cues:)
    return if before_replay.nil? || after_replay.nil? || before_replay.finished?
    return if game.respond_to?(:standard_round_end_sound?) && !game.standard_round_end_sound?
    if before_replay.respond_to?(:accepted_events) && after_replay.respond_to?(:accepted_events)
      previous, current = before_replay.accepted_events.to_a.last, after_replay.accepted_events.to_a.last
      return if previous && current == previous
    end
    return if (cues.compact.map(&:to_s) & COMPLETION_CUES).any?
    return unless game.respond_to?(:round_ended?)

    'round_finished' if game.round_ended?(before_replay: before_replay,
      after_replay: after_replay, history: history)
  end

  def for_event(history, replay, viewer, assets:)
    cues = []
    %i[deal draw play].zip(assets).each do |kind, cue|
      cues << cue if history.any? { |entry| entry.kind == kind }
    end
    result = history.find { |entry| entry.kind == :round_result }
    if result && !result.actor.to_s.empty? && GameRoomParticipants.includes?(replay.players, viewer)
      winners = result.value.is_a?(Array) ? result.value : [result.actor]
      cues << (winners.any? { |player| GameRoomParticipants.same?(player, viewer) } ? 'win1' : 'lose1')
    end
    cues
  end
end
