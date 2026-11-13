require_relative '../support/audio_ball_client'

GameRoomParticipants.configure_display_name(account: 'Viewer', name: '')
GameRoomParticipants.remember_display_name('Alice', 'Anna Kowalska')
GameRoomParticipants.remember_display_name('Bob', 'Jan Nowak')

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
      "#{GameRoomParticipants.short_name(players[host.engine.server])} serves."
    else
      "#{GameRoomParticipants.short_name(players[rotation.server])} will serve against #{GameRoomParticipants.short_name(players[rotation.receiver])}."
    end
    assert(messages.values.all? { |items| items.include?(expected) }, 'Pong serve retained a surname or changed the canonical receiver')
    if team_size == 1
      server = players[host.engine.server]
      caller = match.clients.fetch(players[1-host.engine.server])
      messages.each_value(&:clear)
      assert(caller.request_hurry, 'Pong alias fixture could not request hurry')
      match.advance(8)
      expected = "#{GameRoomParticipants.short_name(server)}, serve within ten seconds or your opponent receives a point."
      assert(messages.values.all? { |items| items == [expected] }, 'Pong direct hurry retained the full name')
      watcher = match.clients.fetch('Watcher')
      observed = players[watcher.send(:observer_side)]
      text = watcher.send(:single_point_spectator_announcement)
      assert(text == "Watching #{GameRoomParticipants.display_name(observed)}. #{GameRoomParticipants.short_name(server)} serves.",
        'Pong spectator orientation lost a full name or its serve retained a surname')
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
      "#{GameRoomParticipants.short_name(players[first])} serves."
    else
      "#{GameRoomParticipants.short_name(players[first])} serves to #{GameRoomParticipants.short_name(players[receiver])}."
    end
    assert(announcements.values.all? { |items| items == [expected] }, 'Audio Ball service bypassed short names or used a wrong receiver')
    caller = players.each_index.find { |seat| seat % 2 != first % 2 }
    assert(match.surfaces.fetch(players[caller]).on_audio_ball_command.call('hurry'), 'Audio Ball alias fixture could not request hurry')
    match.advance(4)
    expected_name = GameRoomParticipants.short_name(players[first])
    assert(match.audios.values.all? { |audio| audio.calls.include?([:hurry, expected_name]) }, 'Audio Ball hurry audio received a surname')
    assert(match.replay.players == players, 'Audio Ball display names changed authenticated seats')
  ensure
    match.close
  end
end

GameRoomParticipants.remember_display_name('Alice', '')
match = AudioBallHarness.new
begin
  messages = realtime_name_speech(match.clients)
  match.advance(12)
  assert(messages.values.all? { |items| items.first == 'Alice serves.' }, 'A missing alias shortened or replaced the ordinary login')
ensure
  match.close
end
puts 'PASS direct Pong and Audio Ball singles/doubles serve and hurry names, full spectator orientation, canonical seats and unaliased login'
