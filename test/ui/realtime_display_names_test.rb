require_relative '../support/audio_ball_client'

def realtime_name_speech(clients)
  clients.to_h do |name, client|
    messages = []
    client.define_singleton_method(:speak) { |text, **_options| messages << text }
    [name, messages]
  end
end

[1, 2].each do |team_size|
  players = team_size == 1 ? %w[Alice Bob] : %w[Alice Bob Carol Dave]
  match = PongHarness.new(players: players, options: {'team_size'=>team_size})
  begin
    messages = realtime_name_speech(match.clients)
    match.advance(500)
    host = match.clients.fetch('Alice')
    rotation = host.send(:rally_state).rotation
    expected = if team_size == 1
      "#{GameRoomParticipants.display_name(players[host.engine.server])} serves."
    else
      "#{GameRoomParticipants.display_name(players[rotation.server])} will serve against #{GameRoomParticipants.display_name(players[rotation.receiver])}."
    end
    assert(messages.values.all? { |items| items.include?(expected) }, 'Pong serve lost an account name or changed the canonical receiver')
    if team_size == 1
      server = players[host.engine.server]
      caller = match.clients.fetch(players[1-host.engine.server])
      messages.each_value(&:clear)
      assert(caller.request_hurry, 'Pong account-name fixture could not request hurry')
      match.advance(8)
      expected = "#{GameRoomParticipants.display_name(server)}, serve within ten seconds or your opponent receives a point."
      assert(messages.values.all? { |items| items == [expected] }, 'Pong direct hurry lost the account name')
      watcher = match.clients.fetch('Watcher')
      observed = players[watcher.send(:observer_side)]
      text = watcher.send(:single_point_spectator_announcement)
      assert(text == "Watching #{GameRoomParticipants.display_name(observed)}. #{GameRoomParticipants.display_name(server)} serves.",
        'Pong spectator orientation or serve lost the account name')
    end
    assert(match.replay.players == players, 'Pong display names changed authenticated seats')
  ensure
    match.close
  end
end

[[%w[Alice Bob], 0], [%w[Alice Bob], 1], [%w[Alice Bob Carol Dave], 2]].each do |players, first|
  match = AudioBallHarness.new(players: players, options: {'team_size'=>players.length/2}, server: first)
  begin
    announcements = match.audios.to_h do |name, audio|
      messages = []
      audio.define_singleton_method(:announce) { |text| messages << text }
      [name, messages]
    end
    match.advance(12)
    receiver = GameRoomAudioBall::Rotation.seat(players.each_index.map { |seat| seat % 2 }, first, 1)
    expected = if players.length == 2
      "#{GameRoomParticipants.display_name(players[first])} serves."
    else
      "#{GameRoomParticipants.display_name(players[first])} serves to #{GameRoomParticipants.display_name(players[receiver])}."
    end
    assert(announcements.values.all? { |items| items == [expected] }, 'Audio Ball service lost account names or used a wrong receiver')
    caller = players.each_index.find { |seat| seat % 2 != first % 2 }
    assert(match.surfaces.fetch(players[caller]).on_audio_ball_command.call('hurry'), 'Audio Ball account-name fixture could not request hurry')
    match.advance(4)
    expected_name = GameRoomParticipants.display_name(players[first])
    assert(match.audios.values.all? { |audio| audio.calls.include?([:hurry, expected_name]) }, 'Audio Ball hurry audio lost the account name')
    assert(match.replay.players == players, 'Audio Ball display names changed authenticated seats')
  ensure
    match.close
  end
end

match = AudioBallHarness.new
begin
  messages = realtime_name_speech(match.clients)
  match.advance(12)
  assert(messages.values.all? { |items| items.first == 'Alice serves.' }, 'A missing alias shortened or replaced the ordinary login')
ensure
  match.close
end
puts 'PASS direct Pong and Audio Ball singles/doubles serve and hurry names, full spectator orientation, canonical seats and unaliased login'
