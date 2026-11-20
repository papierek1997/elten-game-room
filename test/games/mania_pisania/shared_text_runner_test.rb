# encoding: UTF-8
require_relative '../../support/room_interface'
require_relative '../../support/session_runner'
require_relative '../../../lib/mania_pisania/client'

game = GameRoomGames::ManiaPisania.new
[['local', 'Alice'], ['pasted', 'Host']].each do |source, host|
  text = ('Zażółć gęślą jaźń, potem wpisz kolejne słowo. ' * 48).strip
  item = {'text' => text, 'title' => 'Wspólny tekst'}
  id = "local:#{Digest::SHA256.hexdigest(text)}"
  options = game.normalize_options({'variant'=>'free', 'text'=>source}.merge(GameRoomTyping::TextSelection.describe(id, item)))
  h = NativeRoomHarness.new(game:game, users:%w[Alice Bob], options:options)
  h.start
  if host != 'Alice'
    h.add_client(host)
    h.join(host)
    h.as('Alice') do
      h.transports['Alice'].set_observer(h.table, true, actor:'Alice', subject:host)
      h.transports['Alice'].transfer_room_owner(h.table, host)
    end
  end
  runner = runner_for(h, host)
  guest_runner = runner_for(h, 'Bob')
  begin
    clients = [host, 'Bob'].to_h do |name|
      program = EltenGameRoom.allocate
      program.define_singleton_method(:read_json) do |path, default:|
        path == GameRoomTyping::TextLibrary::STORE && name == host ? {'texts'=>{id=>item}} : default
      end
      client = game.build_client(program)
      client.bind_screen(session_id:h.repositories.fetch(name).session_id(h.session), table_id:h.table['__id'],
        owner:host, viewer:name, members:-> { h.users })
      client.define_singleton_method(:covered?) { true }
      client.define_singleton_method(:choose_text) { raise 'The game reopened the local text picker' }
      [name,client]
    end
    publish = lambda do |name, executor|
      h.as(name) do
        snapshot = h.repositories.fetch(name).snapshot_for(h.session)
        replay = game.replay(snapshot.session, snapshot.events, h.repositories.fetch(name))
        clients.fetch(name).before_wait(replay,name)
        data = clients.fetch(name).context_data
        assert(data.empty?, 'A guest offered a text transfer') if name == 'Bob'
        if (pending = data['typing_text_part'])
          assert(!pending['part'].is_a?(Array) && pending['part']['text'].bytesize <= GameRoomTyping::SharedText::CHUNK_BYTES,
            'The client handed the whole text to the runner')
          assert(game.automatic_action(replay, 'Alice', context:GameRoomGames::ActionContext.new(session_id:-1, local_data:data)).nil?,
            'A fragment from another session was eligible for transfer')
        end
        executor.publish_view(session:snapshot.session, replay:replay, busy:false,
          context:GameRoomGames::ActionContext.new(local_data:data))
      end
    end
    step(h, guest_runner, 'Bob', count:2)
    assert(h.replay('Bob').state[:phase] == :setup, 'The guest started without the shared text')
    expected_parts = GameRoomTyping::SharedText.parts(item).length
    (expected_parts + 3).times do
      publish.call(host,runner)
      step(h,runner,host,count:2) # The second pass may have the old UI snapshot.
    end
    h.users.each do |name|
      replay = h.replay(name)
      assert(replay.state[:phase] == :active, 'A prepared multiplayer text did not start without a button')
      assert(replay.state[:shared_text]['text'] == text, 'The received text differs from the selected one')
      assert(replay.state[:text_transfer][:chunks].length == expected_parts, 'A fragment was duplicated or lost')
    end
    publish.call('Bob', guest_runner)
    assert(clients.fetch('Bob').instance_variable_get(:@practice).current_word == 'Zażółć', 'The guest could not type the transferred text')
    h.assert_converged("Automatic #{source} text transfer")
  ensure
    runner.close
    guest_runner.close
  end
end
puts 'PASS shared local/pasted text starts automatically for both players through the native session runner'
