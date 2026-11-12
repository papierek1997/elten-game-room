require_relative '../support/realtime_event_channel'

module ChannelRosterHistoryTest
  module_function

  def fixture
    now = [0.0]
    members = %w[Alice Bob]
    work, events, program = ChannelWork.new, ChannelWork.new, ChannelProgram.new('Alice')
    native_factory = program.method(:communication)
    program.define_singleton_method(:communication) do
      endpoint = native_factory.call
      create = endpoint.method(:create_session)
      number = endpoints.length
      endpoint.define_singleton_method(:create_session) do |**options|
        create.call(**options).tap { |session| session.instance_variable_set(:@id, "history-generation-#{number}") }
      end
      endpoint
    end
    channel = GameRoomRealtime::EventChannel.new(program: program, match: 'history', owner: 'Alice',
      viewer: 'Alice', clock: -> { now.first }, members: -> { members }, work: work, event_work: events)
    channel.enable_events('history-peer', routing: :peers)
    channel.tick; work.finish; channel.tick; work.finish
    session = program.endpoints.first.instance_variable_get(:@created)
    session.participants << ChannelParticipant.new(1, 'Bob')
    channel.tick
    yield channel, session, members, work, now, program
  ensure
    channel&.close
  end

  def packet(channel, number, kind, epoch: channel.epoch)
    GameRoomRealtime::Protocol.encode(match: 'history', epoch: epoch, sequence: number,
      kind: kind, body: {'action' => 'hit'})
  end

  failures = []
  scenarios = {
    invitation_retry_history: lambda do
      fixture do |channel, session, members, work, now|
        32.times do |index|
          visitor = "Visitor#{index}"
          members.replace(['Alice', 'Bob', visitor])
          now[0] += 0.1
          channel.tick
          assert(work.operation, 'A fresh member was not invited through the ordinary finite worker')
          work.finish
          members.replace(%w[Alice Bob])
          channel.tick
          %i[@invite_after @invite_attempts @invite_order].each do |name|
            assert(channel.instance_variable_get(name).empty?, "Departed invitation names accumulate in #{name}")
          end
        end
        assert(session.invites.length == 32, 'Pruning invitation history suppressed a distinct current member')
      end
    end,
    leave_rejoin_watermark: lambda do
      fixture do |channel, session, members, _work, now|
        session.deliver('Bob', packet(channel, 20, 'input'))
        session.deliver_event('Bob', packet(channel, 20, 'event'))
        channel.take_packets; channel.take_events
        members.replace(['Alice'])
        channel.tick
        members.replace(%w[Alice Bob])
        now[0] += 0.1
        session.deliver('bOB', packet(channel, 19, 'input'))
        session.deliver_event('bOB', packet(channel, 19, 'event'))
        assert(channel.take_packets.empty? && channel.take_events.empty?, 'Leave/rejoin admitted an earlier packet')
        session.deliver('BOB', packet(channel, 21, 'input'))
        session.deliver_event('BOB', packet(channel, 21, 'event'))
        assert(channel.take_packets.fetch('bob')['n'] == 21, 'Rejoin lost the next replaceable packet')
        assert(channel.take_events.map { |_, value| value['n'] } == [21], 'Rejoin lost the next ordered event')
      end
    end
  }
  %w[input event].each do |kind|
    scenarios["#{kind}_history_bound"] = lambda do
      fixture do |channel, session, members, work, now, program|
        # A generation may remember256 authenticated names, not merely the
        # at-most32 current participants. Retain departed-name watermarks until
        # the existing generation-safe reconnect; never evict one in place.
        256.times do |index|
          visitor = "Visitor#{index}"
          members.replace(['Alice', visitor])
          data = packet(channel, 1, kind)
          kind == 'input' ? session.deliver(visitor, data) : session.deliver_event(visitor, data)
          received = kind == 'input' ? channel.take_packets : channel.take_events
          assert(received.length == 1, 'An in-bound authenticated sender was lost')
        end
        state_name = kind == 'input' ? :@received_sequences : :@event_sequences
        assert(channel.instance_variable_get(state_name).length == 256, 'In-bound watermarks were discarded')
        old_epoch = channel.epoch
        members.replace(%w[Alice Visitor256])
        data = packet(channel, 1, kind)
        kind == 'input' ? session.deliver('Visitor256', data) : session.deliver_event('Visitor256', data)
        assert(channel.instance_variable_get(state_name).length == 256,
          'Historical authenticated names grew beyond the generation limit')
        assert(channel.instance_variable_get(:@reconnect_requested), 'History exhaustion did not request ordinary recovery')
        assert(channel.take_packets.empty? && channel.take_events.empty?, 'Overflow entered a presentation inbox')
        channel.tick
        assert(!channel.connected? && program.endpoints.first.closed?, 'History exhaustion kept the old endpoint open')
        now[0] += 1
        channel.tick; work.finish; channel.tick; work.finish; channel.tick
        replacement = channel.instance_variable_get(:@session)
        assert(channel.connected? && channel.epoch != old_epoch, 'Recovery did not establish a fresh generation')
        assert(channel.instance_variable_get(:@received_sequences).empty? &&
          channel.instance_variable_get(:@event_sequences).empty?, 'Recovery retained the historical sequence maps')
        # Neither a late old callback nor an old-epoch packet on the current
        # callback may repopulate the replacement's deduplication state.
        session.deliver('Visitor256', data)
        session.deliver_event('Visitor256', packet(channel, 2, 'event', epoch: old_epoch))
        replacement.deliver('Visitor256', packet(channel, 3, 'input', epoch: old_epoch))
        replacement.deliver_event('Visitor256', packet(channel, 3, 'event', epoch: old_epoch))
        assert(channel.take_packets.empty? && channel.take_events.empty?, 'An obsolete generation fed the replacement')
        replacement.deliver('Visitor256', packet(channel, 1, 'input'))
        replacement.deliver_event('Visitor256', packet(channel, 1, 'event'))
        assert(channel.take_packets.fetch('visitor256')['n'] == 1 && channel.take_events.length == 1,
          'A fresh generation could not restart both sequence lanes')
      end
    end
  end
  scenarios.each do |name, operation|
    operation.call
  rescue StandardError => error
    failures << {scenario: name, message: error.message, backtrace: error.backtrace.first(3)}
  end
  assert(failures.empty?, "Channel roster-history failures: #{failures.inspect}")
  puts 'PASS invitation history pruning, leave/rejoin deduplication and bounded reliable/unreliable history with generation-safe recovery'
end
