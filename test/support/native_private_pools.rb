require_relative 'native_room_harness'

# Mirrors the observed native API receipts, including the absence of card
# values in public take records. Loaded only by the private-card scenarios.
module NativePrivatePoolView
  Pool = Struct.new(:view, :id) do
    Draw = Struct.new(:user, :values, keyword_init: true)
    def state; view.pool_state(id); end
    def draw(id)
      value = view.pool_data(self.id)[:draws].fetch(id)
      raise EltenLink::Error, 'Forbidden hand' unless value[:user] == view.user
      Draw.new(user: value[:user], values: value[:values].dup)
    end
    def delete
      raise EltenAPI::LiveSessions::NotOwner unless view.owner?
      view.pool_data_store.delete(id)
    end
  end

  def pool_data_store; @core.instance_variable_get(:@pools) || @core.instance_variable_set(:@pools, {}); end
  def pool_data(id); pool_data_store.fetch(id); end
  def pool(id); Pool.new(self, id); end
  def pools; pool_data_store.keys.map { |id| pool(id) }; end

  def create_pool(min:, max:, private_draws:, message_id:)
    raise EltenAPI::LiveSessions::NotOwner unless owner?
    id = Digest::SHA256.hexdigest(message_id)[0, 32]
    pool_data_store[id] ||= {min: min, max: max,
      remaining: GameRoomRandom.shuffle((min..max).to_a, random: Random.new(707)), draws: {}}
    pool(id)
  end

  def pool_state(id)
    data = pool_data(id)
    {'id' => id, 'min' => data[:min], 'max' => data[:max], 'size' => data[:max] - data[:min] + 1,
      'remaining' => data[:remaining].length, 'private_draws' => true}
  end

  def pool_request(operation, params, pool_id:, draw_id: nil, **_args)
    @calls[operation] += 1
    fault, @fail_next_push = @fail_next_push, nil
    raise EltenAPI::LiveSessions::TimeoutError, 'before pool operation' if fault == :before
    key = [user, operation, params['message_id']]
    replies = @core.instance_variable_get(:@pool_replies) || @core.instance_variable_set(:@pool_replies, {})
    return replies[key] if replies[key]
    data = pool_data(pool_id)
    packet = {'pool_id' => pool_id, 'context' => params['context']}
    response = {'accepted' => true, 'delivery' => 'stack', 'message_id' => params['message_id']}
    if operation == :take
      raise 'Pool exhausted' if data[:remaining].length < params['count']
      values = data[:remaining].shift(params['count'])
      draw_id = params['message_id']
      data[:draws][draw_id] = {user: user, values: values, revealed: []}
      response['draw'] = {'id' => draw_id, 'pool_id' => pool_id, 'user' => user, 'values' => values, 'visibility' => params['visibility']}
      packet.merge!('draw_id' => draw_id, 'count' => values.length, 'remaining' => data[:remaining].length, 'visibility' => params['visibility'])
      packet['values'] = values if params['visibility'] == 'public'
    else
      draw = data[:draws].fetch(draw_id)
      raise 'Not your card' unless draw[:user] == user && (params['values'] - draw[:values]).empty?
      newly_revealed = params['values'] - draw[:revealed]
      draw[:revealed] |= newly_revealed
      response['revealed_values'] = newly_revealed
      if newly_revealed.empty?
        # Native API acknowledges a no-op but appends no stack entry.
        return replies[key] = response.merge('pool'=>pool_state(pool_id))
      end
      packet.merge!('draw_id' => draw_id, 'values' => newly_revealed)
    end
    @core.last_seq += 1
    entry = {'seq' => @core.last_seq, 'message_id' => params['message_id'], 'sender' => {'user' => user},
      'packet' => packet, 'created_at' => @endpoint.broker.now, 'origin' => 'server_pool',
      'pool' => {'id' => pool_id, 'operation' => operation.to_s}}
    @core.entries << entry
    response.merge!('seq' => entry['seq'], 'pool' => pool_state(pool_id))
    replies[key] = response
    @endpoint.broker.deliver if @endpoint.broker.automatic_delivery
    raise EltenAPI::LiveSessions::TimeoutError, 'after pool operation' if fault == :after
    response
  end
end

NativeLiveSessionsBroker::View.prepend(NativePrivatePoolView)
