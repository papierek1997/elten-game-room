require "securerandom"
require "thread"
require_relative "native_tasks"
require_relative "assertions"
Object.include(GameRoomTest::Assertions)

module EltenAPI
  module LiveSessions
    class Error < StandardError; end
    class TimeoutError < Error; end
    class SessionClosed < Error; end
    class NotOwner < Error; end
    class StackFull < Error; end
    class StackPacketTooLarge < Error; end
  end
end

def _(text)
  text
end

module Session
  def self.name
    (Thread.current[:game_room_test_user] || $game_room_test_user).to_s
  end
end

require_relative "../../lib/game_room_transport"
require_relative "../../lib/lobby_repository"
require_relative "../../lib/game_repository"
require_relative "../../lib/table_activity_repository"
require_relative "../../lib/invitation_repository"
require_relative "../../games/base"

class NativeLiveSessionsBroker
  Participant = Struct.new(:id, :user, :metadata, keyword_init: true)
  Info = Struct.new(:sequence, :id, :created_at, :origin, :min, :max, :count, :operation, :pool_id, keyword_init: true) do
    def server_random?; origin == 'server'; end
    def server_pool?; origin == 'server_pool'; end
    def private?; false; end
  end

  Core = Struct.new(
    :id, :metadata, :discovery_metadata, :capacity, :owner, :participants,
    :entries, :views, :closed, :last_seq, :trimmed_through, :stack_entries,
    :stack_entry_bytes, :mutex, :dedup, :visibility, :invitations, :creator,
    keyword_init: true
  )

  Page = Struct.new(:items, :next_cursor, keyword_init: true) do
    def to_a
      items
    end
  end

  attr_reader :cores
  attr_accessor :automatic_delivery

  def initialize
    @cores = {}
    @endpoints = {}
    @automatic_delivery = true
  end

  # Delivery is separate from storage/acknowledgement. Tests can stop one
  # reader, advance others and then catch up by ordered pages or a gap.
  def deliver(user: nil, limit: nil, duplicate: false)
    @cores.values.each do |core|
      core.views.each do |view|
        view.deliver(limit: limit, duplicate: duplicate) if user == nil || view.user == user
      end
    end
  end

  def endpoint(user, fresh: false)
    return Endpoint.new(self, user) if fresh

    @endpoints[user] ||= Endpoint.new(self, user)
  end

  class Endpoint
    attr_reader :user

    def initialize(broker, user)
      @broker = broker
      @user = user
      @sessions = []
      @invitations = []
      @invitation_callbacks = []
      @error_callbacks = []
    end

    def create(metadata:, participant_metadata:, capacity:, visibility:, discovery_metadata:, **options)
      raise EltenLink::Error.new("capacity must be between 2 and 8") unless capacity.between?(2, 8)

      id = SecureRandom.uuid
      core = Core.new(
        id: id,
        metadata: metadata,
        discovery_metadata: discovery_metadata,
        capacity: capacity,
        owner: @user,
        creator: @user,
        participants: {},
        entries: [],
        views: [],
        closed: false, last_seq: 0, trimmed_through: 0,
        stack_entries: options.fetch(:stack_entries),
        stack_entry_bytes: options.fetch(:stack_entry_bytes),
        mutex: Mutex.new, dedup: {}, visibility: visibility, invitations: {}
      )
      @broker.cores[id] = core
      add_view(core, participant_metadata: participant_metadata)
    end

    def discover_sessions(sources: [:created, :invited, :public], **_options)
      items = @broker.cores.values.reject(&:closed).select do |core|
        (sources.include?(:public) && core.visibility == :public) ||
          (sources.include?(:created) && core.creator.casecmp(@user) == 0) ||
          (sources.include?(:invited) && core.invitations[@user.downcase].to_i > Time.now.to_i)
      end.map { |core| Discovery.new(self, core) }
      Page.new(items: items, next_cursor: nil)
    end

    def sessions
      @sessions.reject(&:closed?)
    end

    # Match the native SDK's acknowledgement boundary. Session#leave/close
    # also close locally on failure; these endpoint calls do not.
    def leave_session(session)
      session.remote_leave
    end

    def close_session(session)
      session.remote_close
    end

    def on_invitation(&block)
      @invitation_callbacks << block
    end

    def on_error(&block); @error_callbacks << block; end
    def report_error(error); @error_callbacks.each { |callback| callback.call(error) }; end

    def reject_invitation(identity)
      core = @broker.cores.fetch(identity.id)
      core.invitations.delete(@user.downcase)
      true
    end

    def next_invitation(timeout: nil)
      @invitations.shift
    end

    def deliver_invitation(invitation)
      @invitations << invitation
      @invitation_callbacks.each { |callback| callback.call(invitation) }
    end

    def add_view(core, participant_metadata: {})
      raise EltenAPI::LiveSessions::SessionClosed if core.closed
      if core.visibility == :private && core.owner.casecmp(@user) != 0 && core.invitations[@user.downcase].to_i <= Time.now.to_i
        raise EltenLink::Error.new("not_invited")
      end
      raise EltenLink::Error.new("full") if core.participants.length >= core.capacity

      view = View.new(self, core)
      @sessions << view
      core.views << view
      participant = Participant.new(id: SecureRandom.uuid, user: @user, metadata: JSON.parse(JSON.generate(participant_metadata)))
      core.participants[@user.downcase] = participant
      core.views.each { |candidate| candidate.participant_joined(participant) unless candidate.equal?(view) }
      view
    end

    def broker
      @broker
    end
  end

  class Discovery
    attr_reader :id, :discovery_metadata, :capacity, :participant_count, :join_reason, :visibility, :invitation

    def initialize(endpoint, core)
      @endpoint = endpoint
      @core = core
      @id = core.id
      @visibility = core.visibility
      @invitation = { "invitation_id" => "server:#{core.id}:#{endpoint.user}", "expires_at" => core.invitations[endpoint.user.downcase], "generation" => 1 } if core.invitations[endpoint.user.downcase].to_i > Time.now.to_i
      @discovery_metadata = core.discovery_metadata
      @capacity = core.capacity
      @participant_count = core.participants.length
      @join_reason = @participant_count >= @capacity ? :full : nil
    end

    def can_join?
      @join_reason == nil
    end

    def limits; {"discovery_refresh" => true}; end
    def state; @core.closed ? :closed : :open; end
    def participants
      return nil unless @visibility == :public
      @core.participants.values.map { |person| {'id' => person.id, 'user' => person.user} }
    end

    def refresh(timeout: 45)
      @discovery_metadata = @core.discovery_metadata
      @participant_count = @core.participants.length
      @join_reason = @participant_count >= @capacity ? :full : nil
      self
    end

    def join(participant_metadata: {})
      raise "full" if !can_join?

      @endpoint.add_view(@core, participant_metadata: participant_metadata)
    end
  end

  class Invitation
    attr_reader :id, :metadata, :invitation_metadata, :inviter, :expires_at

    def initialize(target, core, inviter, metadata)
      @target = target
      @core = core
      @id = core.id
      @metadata = core.metadata
      @invitation_metadata = metadata
      @inviter = Participant.new(id: "inviter", user: inviter)
      @expires_at = Time.now.to_i + 600
      @pending = true
    end

    def pending?
      @pending
    end

    def accept(participant_metadata: {})
      @pending = false
      @target.add_view(@core, participant_metadata: participant_metadata)
    end

    def reject
      @pending = false
      @core.invitations.delete(@target.user.downcase)
      true
    end
  end

  class View
    attr_reader :id, :metadata, :capacity
    def visibility; @core.visibility; end
    attr_accessor :fail_next_push, :fail_next_read, :fail_next_trim, :next_random_values
    attr_reader :calls

    def initialize(endpoint, core)
      @endpoint = endpoint
      @core = core
      @id = core.id
      @metadata = core.metadata
      @capacity = core.capacity
      @stack_callbacks = []
      @join_callbacks = []
      @left_callbacks = []
      @closed_callbacks = []
      @owner_callbacks = []
      @discovery_callbacks = []
      @closed = false
      @gap_callbacks = []
      @delivery_cursor = 0
      @calls = Hash.new(0)
    end

    def user; @endpoint.user; end

    def limits
      {"max_stack_entry_bytes" => @core.stack_entry_bytes, "max_stack_entries" => @core.stack_entries}
    end

    def participants
      @core.participants.values
    end

    def participant(id)
      participants.find { |participant| participant.id.to_s == id.to_s }
    end

    def owner
      participants.find { |participant| participant.user.casecmp(@core.owner) == 0 }
    end

    def owner?
      @endpoint.user.casecmp(@core.owner) == 0
    end

    def discovery_metadata; @core.discovery_metadata; end
    def on_owner_changed(&block); @owner_callbacks << block; end
    def on_discovery_metadata_changed(&block); @discovery_callbacks << block; end
    def transfer_ownership(target, timeout: 45)
      raise EltenAPI::LiveSessions::NotOwner unless owner?
      raise ArgumentError, "Unknown participant" unless participants.include?(target)
      previous = owner
      @core.owner = target.user
      @core.views.each { |view| view.instance_variable_get(:@owner_callbacks).each { |cb| cb.call(previous, target) } }
      target
    end

    def update_discovery_metadata(metadata, timeout: 45)
      raise EltenAPI::LiveSessions::NotOwner unless owner?
      raise ArgumentError, "discovery too large" if JSON.generate(metadata).bytesize > 1024
      @calls[:discovery_update] += 1
      @core.discovery_metadata = JSON.parse(JSON.generate(metadata))
      @core.views.each { |view| view.instance_variable_get(:@discovery_callbacks).each { |cb| cb.call(@core.discovery_metadata) } }
    end

    def closed?
      @closed || @core.closed
    end

    def stack_state
      { "last_seq" => @core.last_seq, "count" => @core.entries.length, "trimmed_through" => @core.trimmed_through }
    end

    def stack_push(packet, message_id:)
      (@push_attempts ||= []) << [message_id, JSON.parse(JSON.generate(packet))]
      @calls[:push] += 1
      raise EltenAPI::LiveSessions::SessionClosed if closed?
      fault, @fail_next_push = @fail_next_push, nil
      raise EltenAPI::LiveSessions::TimeoutError, "before push" if fault == :before
      raise fault if fault.is_a?(Exception)
      key = [user, message_id]
      @core.mutex.synchronize do
        previous = @core.dedup[key]
        return { "entry" => { "seq" => previous }, "stack" => stack_state } if previous

        raise EltenAPI::LiveSessions::StackFull if @core.entries.length >= @core.stack_entries
        raise EltenAPI::LiveSessions::StackPacketTooLarge if JSON.generate(packet).bytesize > @core.stack_entry_bytes
        sequence = @core.last_seq + 1
        created_at = Time.now.to_i
        entry = {
          "seq" => sequence,
          "message_id" => message_id,
          "sender" => { "user" => @endpoint.user },
          "sender_id" => @core.participants.fetch(@endpoint.user.downcase).id,
          "packet" => packet,
          "created_at" => created_at
        }
        @core.entries << entry
        @core.last_seq = sequence
        @core.dedup[key] = sequence
      end
      @endpoint.broker.deliver if @endpoint.broker.automatic_delivery
      raise EltenAPI::LiveSessions::TimeoutError, "after push" if fault == :after
      { "entry" => { "seq" => @core.dedup.fetch(key) }, "stack" => stack_state }
    end

    def stack_read(after:, limit:)
      @calls[:read] += 1
      raise EltenAPI::LiveSessions::SessionClosed if closed?
      fault, @fail_next_read = @fail_next_read, nil
      raise fault if fault
      @core.mutex.synchronize do
        gap = { "from" => after + 1, "to" => @core.trimmed_through } if after < @core.trimmed_through
        after = [after, @core.trimmed_through].max
        entries = @core.entries.select { |entry| entry["seq"] > after.to_i }.first(limit)
        cursor = entries.empty? ? after.to_i : entries.last["seq"]
        { "session_id" => id, "entries" => entries, "cursor" => cursor, "has_more" => @core.entries.any? { |entry| entry["seq"] > cursor }, "gap" => gap, "through" => @core.last_seq }
      end
    end

    # Native random metadata is outside the participant-controlled packet.
    def stack_push_random(min:, max:, count:, context:, message_id:)
      @calls[:random] += 1
      fault, @fail_next_push = @fail_next_push, nil
      raise EltenAPI::LiveSessions::TimeoutError, 'before random push' if fault == :before
      raise fault if fault.is_a?(Exception)
      raise EltenAPI::LiveSessions::SessionClosed if closed?
      entry = @core.mutex.synchronize do
        previous = @core.entries.find { |item| item['message_id'] == message_id && item.dig('sender', 'user') == user }
        if previous
          raise ArgumentError, 'random parameters changed' unless previous['random'] == {'min'=>min, 'max'=>max, 'count'=>count} && previous.dig('packet','context') == context
          next previous
        end
        raise EltenAPI::LiveSessions::StackFull if @core.entries.length >= @core.stack_entries
        values, @next_random_values = @next_random_values, nil
        values ||= Array.new(count) { SecureRandom.random_number(max - min + 1) + min }
        raise ArgumentError, 'Invalid random test values' unless values.length == count && values.all? { |n| n.between?(min, max) }
        packet = {'values' => values, 'context' => JSON.parse(JSON.generate(context))}
        raise EltenAPI::LiveSessions::StackPacketTooLarge if JSON.generate(packet).bytesize > @core.stack_entry_bytes
        sequence = @core.last_seq + 1
        result = {'seq'=>sequence, 'message_id'=>message_id, 'sender'=>{'user'=>user},
          'sender_id'=>@core.participants.fetch(user.downcase).id, 'created_at'=>Time.now.to_i,
          'packet'=>packet, 'origin'=>'server', 'random'=>{'min'=>min, 'max'=>max, 'count'=>count}}
        @core.entries << result
        @core.last_seq = sequence
        @core.dedup[[user, message_id]] = sequence
        result
      end
      @endpoint.broker.deliver if @endpoint.broker.automatic_delivery
      raise EltenAPI::LiveSessions::TimeoutError, 'after random push' if fault == :after
      entry.merge('stack' => stack_state)
    end

    def stack_trim(through:)
      @calls[:trim] += 1
      raise EltenAPI::LiveSessions::NotOwner if !owner?
      raise EltenAPI::LiveSessions::SessionClosed if closed?
      fault, @fail_next_trim = @fail_next_trim, nil
      raise EltenAPI::LiveSessions::TimeoutError, "before trim" if fault == :before
      @core.mutex.synchronize do
        @core.entries.reject! { |entry| entry["seq"] <= through }
        @core.trimmed_through = [@core.trimmed_through, through].max
      end
      raise EltenAPI::LiveSessions::TimeoutError, "after trim" if fault == :after
      stack_state
    end

    def deliver(limit: nil, duplicate: false)
      return if closed?
      if @delivery_cursor < @core.trimmed_through
        gap = { "from" => @delivery_cursor + 1, "to" => @core.trimmed_through }
        @delivery_cursor = gap["to"]
        @gap_callbacks.each { |callback| callback.call(gap) }
      end
      entries = @core.entries.select { |entry| entry["seq"] > @delivery_cursor }
      entries = entries.first(limit) if limit
      entries.each do |entry|
        @delivery_cursor = entry["seq"]
        sender = Participant.new(user: entry.dig("sender", "user"))
        info = Info.new(sequence: entry["seq"], id: entry["message_id"], created_at: entry["created_at"],
          origin: entry['origin'], min: entry.dig('random', 'min'), max: entry.dig('random', 'max'), count: entry.dig('random', 'count'),
          operation: entry.dig('pool', 'operation'), pool_id: entry.dig('pool', 'id'))
        (duplicate ? 2 : 1).times { stack_message(sender, entry["packet"], info) }
      end
    end

    def on_stack_message(with_metadata: false, &block)
      @stack_callbacks << block
    end

    def on_stack_gap(&block); @gap_callbacks << block; end
    def on_participant_joined(&block); @join_callbacks << block; end
    def on_participant_left(&block); @left_callbacks << block; end
    def on_closed(&block); @closed_callbacks << block; end

    def stack_message(sender, packet, info)
      @stack_callbacks.each { |callback| callback.call(sender, packet, info) }
    end

    def participant_joined(participant)
      @join_callbacks.each { |callback| callback.call(participant) }
    end

    def invite(user, metadata: {})
      raise EltenAPI::LiveSessions::SessionClosed if closed?
      target = @endpoint.broker.endpoint(user)
      invitation = Invitation.new(target, @core, @endpoint.user, metadata)
      @core.invitations[user.downcase] = invitation.expires_at
      target.deliver_invitation(invitation)
      { "expires_at" => invitation.expires_at }
    end

    def leave
      return false if closed?
      confirmed = false
      begin
        @endpoint.leave_session(self)
        confirmed = true
      ensure
        close_local(:left, confirmed: confirmed)
      end
      true
    end

    def remote_leave
      was_owner = owner?
      if was_owner && @core.participants.size > 1
        successor = @core.participants.values.find { |entry| entry.user.casecmp(@endpoint.user) != 0 }
        transfer_ownership(successor)
      end
      participant = @core.participants.delete(@endpoint.user.downcase)
      @core.views.each { |view| view.participant_left(participant) unless view.equal?(self) }
      true
    end

    def close_local(reason, confirmed: false, operation: :leave)
      return false if @closed
      @closed = true
      @closed_callbacks.each { |callback| callback.call(reason) }
      true
    end

    def participant_left(participant)
      @left_callbacks.each { |callback| callback.call(participant, :left) }
    end

    def close
      confirmed = false
      begin
        @endpoint.close_session(self)
        confirmed = true
      ensure
        close_local(:closed, confirmed: confirmed, operation: :close)
      end
      true
    end

    def remote_close
      raise EltenAPI::LiveSessions::NotOwner if !owner?
      @core.closed = true
      @core.views.each do |view|
        view.instance_variable_set(:@closed, true)
        view.instance_variable_get(:@closed_callbacks).each { |callback| callback.call(:closed) }
      end
      true
    end
  end
end

module EltenLink
  class Error < StandardError
    attr_reader :code

    def initialize(message, code: nil)
      @code = code || message
      super(message)
    end
  end

  module Apps
    def self.table(client, _uuid, name)
      assert(%w[game_room_users table_activity].include?(name), "Room or game state requested a legacy table")
      client
    end
  end
end

ProgramDouble = Struct.new(:live_sessions)

class ActivityTableDouble
  attr_reader :calls

  def initialize(denied: false)
    @rows = []
    @calls = []
    @denied = denied
  end

  def record_request(operation)
    @calls << operation
    raise EltenLink::Error.new("apps.tables.stamp_required") if @denied
  end

  def insert(values)
    record_request(:insert)
    row = values.merge("__id" => @rows.length + 1, "__insertion_user" => values["actor"])
    @rows << row
    row
  end

  def select(where: nil, order: nil, limit: nil, **_options)
    record_request(:select)
    rows = @rows.dup
    rows = rows.select { |row| where.all? { |key, value| row[key] == value } } if where
    rows.last(limit || rows.length)
  end
end
