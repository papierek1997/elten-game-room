# frozen_string_literal: true

require 'digest'
require 'thread'
require_relative 'game_snapshot'
require_relative 'game_participants'

# One owned, authenticated prefix. A changed earlier record, actor, session or
# dependency invalidates it; returned reducers never share its mutable model.
class GameRoomReplayCache
  MAX_BYTES = 8 * 1024 * 1024
  Entry = Data.define(:key, :identities, :count, :signature, :checkpoint)

  class Input
    attr_reader :session, :players, :events, :retained_bytes, :retention_bytes

    def initialize(session, events, repository, previous: nil)
      @session, @players = Marshal.load(Marshal.dump([session, repository.players_for(session)]))
      sealed = events.is_a?(GameRoomSnapshot::Log) && events.frozen?
      @source = sealed ? events : nil
      @authentication = repository.replay_authentication_identity if sealed && repository.respond_to?(:replay_authentication_identity)
      reusable = @authentication && previous && previous.instance_variable_get(:@authentication) == @authentication &&
        previous.session == @session && previous.players == @players
      prior_source = previous.instance_variable_get(:@source) if reusable
      if prior_source && prior_source.equal?(events)
        %i[by_event sizes retained_bytes borrowed_bytes signatures records events retention_bytes].each do |name|
          instance_variable_set("@#{name}", previous.instance_variable_get("@#{name}"))
        end
        return
      end
      prefix = prior_source && prior_source.length <= events.length &&
        prior_source.each_with_index.all? { |item, index| item.equal?(events[index]) } ? prior_source.length : 0
      @by_event = prefix.positive? ? previous.instance_variable_get(:@by_event).dup : {}.compare_by_identity
      @sizes = prefix.positive? ? previous.instance_variable_get(:@sizes).dup : []
      @retained_bytes = prefix.positive? ? previous.retained_bytes : 0
      @borrowed_bytes = prefix.positive? ? previous.instance_variable_get(:@borrowed_bytes) : 0
      @signatures = prefix.positive? ? previous.instance_variable_get(:@signatures).dup : [Digest::SHA256.digest('authenticated-replay-prefix-v1').freeze]
      @records = prefix.positive? ? previous.instance_variable_get(:@records).dup : []
      events.to_a.drop(prefix).each_with_index do |event, offset|
        index = prefix + offset
        prior = previous && previous.record_at(index)
        # Reuse only owned, sealed values. Recheck authentication even for an
        # unchanged raw event; its current controller interpretation may differ.
        row = if prior && prior.first.eql?(event)
          prior.first
        elsif sealed
          event
        else
          Marshal.load(Marshal.dump(event))
        end
        actor = repository.actor_of(row, @session)
        actor = actor.dup.freeze if actor.is_a?(String)
        record = [row, repository.event_id(row), actor]
        if prior && record.eql?(prior)
          record = prior
        else
          seal(record)
        end
        if record.equal?(prior) && @signatures.last == previous.signature(index)
          @signatures << previous.signature(index + 1)
          @sizes << previous.record_bytes(index)
        else
          encoded=Marshal.dump(record)
          @signatures << Digest::SHA256.digest(@signatures.last + encoded).freeze
          @sizes << encoded.bytesize
        end
        @retained_bytes += @sizes.last
        @borrowed_bytes += @sizes.last if sealed && row.equal?(event)
        @by_event[row] = [index, record].freeze
        @records << record
      end
      @events = if prefix.positive?
        (previous.events.dup.concat(@records.drop(prefix).map(&:first))).freeze
      else
        @records.map(&:first).freeze
      end
      @by_event.freeze
      @records.freeze
      @signatures.freeze
      @sizes.freeze
      # Borrowed rows already belong to the bounded native log. Account for
      # this cache's indexes/digests, not another imagined copy of those rows.
      @retention_bytes = @retained_bytes - @borrowed_bytes + @records.length * 192
    end

    def actor_of(event, _session = nil); @by_event.fetch(event).last[2]; end
    def event_id(event); @by_event.fetch(event).last[1]; end
    def index_of(event); @by_event.fetch(event).first; end

    def signature(count = @records.length)
      @signatures.fetch(count)
    end

    def record_at(index); @records[index]; end
    def record_bytes(index); @sizes.fetch(index); end

    private
    def seal(value)
      case value
      when Hash then value.each { |key,item| seal(key); seal(item) }
      when Array, Struct then value.each { |item| seal(item) }
      end
      value.freeze
    end
  end

  def initialize
    @lock = Mutex.new
    @generation = 0
    @entry = nil
  end

  # Serialized owned checkpoint/log budget, not a process-memory measurement.
  # Consumers retaining additional prepared inputs can drop those too when
  # the bounded checkpoint was refused, without inspecting private Entry state.
  def retained_bytes
    @lock.synchronize { @entry ? @entry.checkpoint.bytesize : 0 }
  end

  # Reducer checkpoints precede any presentation-only pending transitions.
  # A historical view may be read without evicting the longer current prefix.
  def reduce(input, context:, identities: [])
    key = Digest::SHA256.digest(Marshal.dump([input.session, input.players, context, GameRoomParticipants.names_revision])).freeze
    entry, ticket = @lock.synchronize { [@entry, @generation += 1] }
    count = input.events.length
    prefix = 0
    checkpoint = nil
    same_context = entry && entry.key == key && entry.identities.length == identities.length &&
      entry.identities.zip(identities).all? { |left, right| left.equal?(right) }
    if same_context && entry.count <= count
      if input.signature(entry.count) == entry.signature
        prefix = entry.count
        checkpoint = entry.checkpoint.restore
        return checkpoint if prefix == count
      end
    end
    result = yield(checkpoint, prefix)
    signature = input.signature
    encoded = GameRoomSnapshot.capture(result)
    @lock.synchronize do
      if ticket == @generation
        historical = same_context && entry.equal?(@entry) && @entry.count > count
        unless historical
          @entry = encoded.bytesize <= MAX_BYTES ? Entry.new(key, identities.dup.freeze, count, signature, encoded) : nil
        end
      end
    end
    result
  end
end
