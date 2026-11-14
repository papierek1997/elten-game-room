require_relative 'game_participants'
require_relative 'participant_decision_events'
require_relative 'game_snapshot'
require 'digest'

# A place in the match keeps its cards/score/team when its occupant changes.
# The stored log is immutable: the adapter maps actors by their place at the
# time of the event, not by their current username. This also supports swaps.
# Reuse each game's archive remapping contract instead of replacing arbitrary
# strings in its state (a username could also be a card, colour or word).
module GameRoomParticipantReplay
  class Repository
    def initialize(source, players)
      @source, @players = source, players
    end

    def players_for(_session); @players; end
    def actor_of(event, _session = nil); event.fetch('__replay_actor'); end
    def event_id(event); @source.event_id(event); end
  end

  def self.roster_at(session, event_id = Float::INFINITY)
    changes = session.fetch('__seat_changes', [])
    change = changes.reverse.find { |row| row.fetch('id') < event_id }
    change ? change.fetch('players') : session.fetch('__initial_players', session.fetch('__players'))
  end

  # Prepended to game subclasses, including subclasses of CardGame/TileGame.
  # Removing the metadata in the delegated session makes nested wrappers inert.
  def replay(session, events, repository)
    changes = session.fetch('__seat_changes', [])
    return super if changes.empty?

    participants = repository.players_for(session)
    plain = session.reject { |key, _| %w[__seat_changes __initial_players].include?(key) }
    if replay_participant_transitions?
      previous = session.fetch('__initial_players')
      plain['__replay_participant_transitions'] = changes.map do |change|
        following = change.fetch('players')
        seats = previous.each_index.select { |seat| !GameRoomParticipants.same?(previous[seat], following[seat]) }
        previous = following
        {'id' => change.fetch('id'), 'seats' => seats}
      end
    end
    originals = events.to_h { |event| [repository.event_id(event), event] }
    build = lambda do |roster, prefix|
      adapted = prefix.map do |event|
        previous = GameRoomParticipantReplay.roster_at(session, repository.event_id(event))
        mapping = previous.each_with_index.to_h { |player, index| [player.downcase, roster.fetch(index)] }
        actor = mapping.fetch(repository.actor_of(event, session).to_s.downcase, '')
        event.merge('__replay_actor' => actor, 'actor' => actor,
          'value' => restored_event_value(event, mapping))
      end
      super(plain.merge('__players' => roster), adapted, Repository.new(repository, roster))
    end
    result = build.call(participants, events)

    # A corrected earlier event must invalidate its historical presentation,
    # even if the event count and final ID did not change. Keep fingerprints,
    # not references to mutable input hashes. Model replay is never cached.
    key = Digest::SHA256.digest(Marshal.dump([session['__id'], session['options'], session['__initial_players'], changes]))
    cache = @participant_history_cache
    cache = {key: key, segments: {}} unless cache && cache[:key] == key
    @participant_history_cache = cache
    history = []
    lower = -1
    roster = session.fetch('__initial_players')
    changes.each do |change|
      upper = change.fetch('id')
      prefix = events.take_while { |event| repository.event_id(event) < upper }
      segment_key = [lower, upper]
      signature = Digest::SHA256.digest(Marshal.dump(prefix))
      segment = cache[:segments][segment_key]
      unless segment && segment[:signature] == signature
        entries = build.call(roster, prefix).history.select do |entry|
          entry.event_id.to_i > lower && entry.event_id.to_i < upper
        end.freeze
        segment = cache[:segments][segment_key] = {signature: signature, entries: entries}
      end
      history.concat(GameRoomSnapshot.copy(segment[:entries]))
      lower, roster = upper, change.fetch('players')
    end
    history.concat(result.history.select { |entry| entry.event_id.to_i > lower })
    result.history = history
    GameRoomParticipantDecisionEvents.attach(result, result.accepted_events)
    result.accepted_events = result.accepted_events.map { |event| originals.fetch(repository.event_id(event)) }
    result
  end
end
