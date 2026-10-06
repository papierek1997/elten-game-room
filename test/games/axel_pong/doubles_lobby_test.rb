require_relative "../../support/axel_pong_doubles_lobby"

module PongDoublesLobbyTest

test("real creation form defaults to Single and persists Doubles on selection") do
  ["Single", "Doubles"].each do |mode|
    app = PongDoublesLobbyApp.new
    create_pong(app, mode: mode)
    assert(app.notices.empty?, "A valid creation choice raised an error")
  end
end

test("manual 2+2 through start_new_game preserves session seats and excludes observers") do
  app = PongDoublesLobbyApp.new
  row = create_pong(app)
  bob = join(app, row, "Bob")
  %w[Carol Dave].each { |name| join(app, row, name) }
  watcher = join(app, row, "Watcher", observer: true)
  players = %w[Alice Bob Carol Dave]
  result = with_forms(
    change_team(players, [0, 1, 0, 1], 1), choose_team(1, 0),
    change_team(players, [0, 0, 0, 1], 2), choose_team(0, 1),
    start_teams(players, [0, 0, 1, 1])
  ) { app.send(:start_new_game, row) }
  stored = assert_started(app, row, result, players, [0, 0, 1, 1])
  [bob, watcher].each do |repository|
    remote = repository.session_for_table(row, force: true)
    assert(remote != nil && remote["__id"] == stored["__id"], "A player or observer could not read the started session")
    assert(JSON.parse(remote["options"])["team_seats"] == [0, 0, 1, 1], "A remote reader lost manually chosen teams")
    assert(repository.players_for(remote) == players, "A remote reader sees the observer as a player")
  end
  assert(app.notices.empty?, "A valid manual doubles start raised an error")
end

test("cancelling the real creation form creates no room or session") do
  app = PongDoublesLobbyApp.new
  create_pong(app, cancel: true)
  assert(app.broker.cores.empty?, "Cancelling creation wrote a native room")
  assert(app.opened_tables.empty? && app.network_calls.empty?, "Cancelling creation opened a table or requested a network write")
end

test("Choose teams randomly shuffles people into valid teams without starting") do
  app = PongDoublesLobbyApp.new
  row = create_pong(app)
  players = %w[Alice Bob Carol Dave]
  players.drop(1).each { |name| join(app, row, name) }
  result = with_forms(
    change_team(players, [0, 1, 0, 1], 1), choose_team(1, 0),
    change_team(players, [0, 0, 0, 1], 2), choose_team(0, 1),
    lambda do |form|
      list = team_form(form, players, [0, 0, 1, 1])
      assert(list.index == 2, "Manual team selection reset the player cursor")
      button(form, "Choose teams randomly").trigger(:press)
    end,
    lambda do |form|
      list = form.fields.first
      assert(list.options.map { |text| text.split(', team ').first }.sort == players.sort, "Randomization lost players")
      assert(list.index == 2, "Automatic assignment reset the player cursor")
      button(form, "Accept teams").trigger(:press)
    end
  ) { app.send(:start_new_game, row) }
  chosen = JSON.parse(app.lobby.snapshot_for(row, force: true).table["game_options"])["team_seats"]
  assert(chosen.sort == [0, 0, 1, 1], "Randomized teams are not 2+2")
  assert_started(app, row, result, players, chosen)
  assert(app.notices.empty?, "Automatic 2+2 assignment raised an error")
end

test("cancelling team selection after a manual change writes no session") do
  app = PongDoublesLobbyApp.new
  row = create_pong(app)
  players = %w[Alice Bob Carol Dave]
  players.drop(1).each { |name| join(app, row, name) }
  before = app.broker.cores.values.map(&:last_seq)
  result = with_forms(
    change_team(players, [0, 1, 0, 1], 1), choose_team(1, 0),
    lambda do |form|
      team_form(form, players, [0, 0, 0, 1])
      form.cancel_button.trigger(:press)
    end
  ) { app.send(:start_new_game, row) }
  assert(result == nil, "Cancel returned a session")
  assert_no_game(app, row)
  assert(app.broker.cores.values.map(&:last_seq) == before, "Cancel pushed a native stack record")
  assert(!app.network_calls.include?("Starting game"), "Cancel reached the session-write task")
end

test("cancelling the individual team chooser preserves seats without starting") do
  app = PongDoublesLobbyApp.new
  row = create_pong(app)
  players = %w[Alice Bob Carol Dave]
  players.drop(1).each { |name| join(app, row, name) }
  before = app.broker.cores.values.map(&:last_seq)
  result = with_forms(
    change_team(players, [0, 1, 0, 1], 1),
    lambda do |form|
      assert(form.fields.first.header == "Choose a team", "Enter bypassed the team chooser")
      form.fields.first.index = 0
      form.cancel_button.trigger(:press)
    end,
    lambda do |form|
      list = team_form(form, players, [0, 1, 0, 1])
      assert(list.index == 1, "Cancelling the team chooser lost the selected player")
      assert_no_game(app, row)
      form.cancel_button.trigger(:press)
    end
  ) { app.send(:start_new_game, row) }
  assert(result == nil, "Cancelling the team chooser started a game")
  assert_no_game(app, row)
  assert(app.broker.cores.values.map(&:last_seq) == before, "Cancelled team selection wrote to the native stack")
end

test("Start rejects an incomplete 3+1 selection and keeps the chooser open") do
  app = PongDoublesLobbyApp.new
  row = create_pong(app)
  players = %w[Alice Bob Carol Dave]
  players.drop(1).each { |name| join(app, row, name) }
  invalid_form = nil
  result = with_forms(
    change_team(players, [0, 1, 0, 1], 1), choose_team(1, 0),
    lambda do |form|
      team_form(form, players, [0, 0, 0, 1])
      invalid_form = form
      button(form, "Accept teams").trigger(:press)
      assert(app.notices == ["Team 1 must contain exactly 2 players; it currently contains 3."], "An incomplete team did not explain why Start was rejected")
      assert_no_game(app, row)
    end,
    lambda do |form|
      assert(form.equal?(invalid_form), "Invalid Start dismissed or replaced the team chooser")
      team_form(form, players, [0, 0, 0, 1])
      form.cancel_button.trigger(:press)
    end
  ) { app.send(:start_new_game, row) }
  assert(result == nil, "An incomplete team started a session")
  assert_no_game(app, row)
end

{"Single" => [1, 3, 4, 5], "Doubles" => [1, 2, 3, 5]}.each do |mode, counts|
  counts.each do |count|
    test("#{mode} rejects #{count} players before opening teams or writing a session") do
      app = PongDoublesLobbyApp.new
      row = create_pong(app, mode: mode)
      %w[Bob Carol Dave Eve].first(count - 1).each { |name| join(app, row, name) }
      before = app.broker.cores.values.map(&:last_seq)
      result = with_forms { app.send(:start_new_game, row) }
      assert(result == nil, "#{mode} accepted #{count} players")
      assert_no_game(app, row)
      assert(app.notices.length == 1, "Wrong player count did not produce one validation message")
      if count.between?(2, 4)
        expected = mode == "Doubles" ? "Doubles requires exactly four players." : "Single requires exactly two players."
        assert(app.notices.first == expected, "Wrong player count lost its match-specific explanation")
      end
      assert(app.broker.cores.values.map(&:last_seq) == before, "Wrong player count wrote to the native stack")
    end
  end
end

test("an observer cannot fill the fourth Doubles seat") do
  app = PongDoublesLobbyApp.new
  row = create_pong(app)
  %w[Bob Carol].each { |name| join(app, row, name) }
  join(app, row, "Watcher", observer: true)
  room = app.lobby.snapshot_for(row, force: true)
  assert(room.members.length == 4 && room.game_participants == %w[Alice Bob Carol], "Observer setup did not leave three actual players")
  result = with_forms { app.send(:start_new_game, row) }
  assert(result == nil && app.notices == ["Doubles requires exactly four players."], "An observer satisfied the Doubles player count")
  assert_no_game(app, row)
end

test("a same-sized roster change after choosing teams rejects the start") do
  app = PongDoublesLobbyApp.new
  row = create_pong(app)
  players = %w[Alice Bob Carol Dave]
  players.drop(1).each { |name| join(app, row, name) }
  result = with_forms(
    change_team(players, [0, 1, 0, 1], 1), choose_team(1, 0),
    change_team(players, [0, 0, 0, 1], 2), choose_team(0, 1),
    lambda do |form|
      team_form(form, players, [0, 0, 1, 1])
      app.lobby.set_observer(row, "Alice", true)
      join(app, row, "Eve")
      latest = app.lobby.snapshot_for(row, force: true)
      assert(latest.game_participants == %w[Bob Carol Dave Eve], "Roster-change setup did not replace a player at the same count")
      button(form, "Accept teams").trigger(:press)
    end
  ) { app.send(:start_new_game, row) }
  assert(result == nil, "Teams were started against a changed roster")
  assert(app.notices == ["The users at the table changed while teams were being selected. Please start again."], "Roster change did not request another selection")
  assert_no_game(app, row)
  assert(!app.network_calls.include?("Starting game"), "Changed roster reached the session-write task")
end

test("an observer joining during selection does not change or block teams") do
  app = PongDoublesLobbyApp.new
  row = create_pong(app)
  players = %w[Alice Bob Carol Dave]
  players.drop(1).each { |name| join(app, row, name) }
  result = with_forms(
    lambda do |form|
      team_form(form, players, [0, 1, 0, 1])
      join(app, row, "Watcher", observer: true)
      button(form, "Accept teams").trigger(:press)
    end
  ) { app.send(:start_new_game, row) }
  assert_started(app, row, result, players, [0, 1, 0, 1])
  assert(app.notices.empty?, "An observer-only change invalidated the selected roster")
end

test("default Single starts two players without a team form") do
  app = PongDoublesLobbyApp.new
  row = create_pong(app, mode: "Single")
  join(app, row, "Bob")
  join(app, row, "Watcher", observer: true)
  result = with_forms { app.send(:start_new_game, row) }
  stored = assert_started(app, row, result, %w[Alice Bob], nil)
  assert(JSON.parse(stored["options"])["team_size"] == 0, "Default Single silently became Doubles")
  assert(app.notices.empty?, "Default Single was rejected")
end

test("old options without team_size still start Single and preserve other rules") do
  [{}, {"arcade" => true, "difficulty" => 3, "target" => 7}].each do |options|
    app = PongDoublesLobbyApp.new
    row = app.lobby.create_table(name: "Old Pong options", game: "axel_pong", owner: "Alice", game_options: JSON.generate(options)).table
    join(app, row, "Bob")
    result = with_forms { app.send(:start_new_game, row) }
    stored = assert_started(app, row, result, %w[Alice Bob], nil)
    restored = JSON.parse(stored["options"])
    assert(restored["team_size"] == 0, "An old table without team_size was not Single")
    assert(options.all? { |key, value| restored[key] == value }, "Migrating old Single options changed existing rules")
    assert(app.notices.empty?, "An old Single table was rejected")
  end
end

test("mixed humans and bots start Doubles without requiring bot live membership") do
  app = PongDoublesLobbyApp.new
  row = create_pong(app)
  join(app, row, "Bob")
  join(app, row, "Watcher", observer: true)
  2.times { assert(app.lobby.add_bot(row).updated?, "The test could not add a computer") }
  room = app.lobby.snapshot_for(row, force: true)
  players = room.game_participants
  assert(players.first(2) == %w[Alice Bob] && players.length == 4, "Mixed setup did not contain two humans and two bots")
  assert(players.last(2).all? { |player| GameRoomParticipants.bot?(player) }, "Mixed setup lost bot identities")
  result = with_forms(start_teams(players, [0, 1, 0, 1])) { app.send(:start_new_game, row) }
  stored = assert_started(app, row, result, players, [0, 1, 0, 1])
  assignment = app.send(:game_definition, "axel_pong").team_assignment(JSON.parse(stored["options"]), players: players)
  assert(assignment.valid? && assignment.members_for(0) == [players[0], players[2]], "Mixed doubles did not produce a valid human/bot pair")
  assert(app.notices.empty?, "Bot participants were mistaken for disconnected humans")
end

[1, 2, 3].each do |human_count|
  test("#{human_count} humans and #{4 - human_count} bots use the standard Doubles team selector") do
    app = PongDoublesLobbyApp.new
    row = create_pong(app)
    %w[Bob Carol].first(human_count - 1).each { |name| join(app, row, name) }
    (4 - human_count).times { assert(app.lobby.add_bot(row).updated?, "The test could not add a doubles bot") }
    players = app.lobby.snapshot_for(row, force: true).game_participants
    assert(players.count { |player| GameRoomParticipants.bot?(player) } == 4 - human_count, "Wrong bot count at the table")
    result = with_forms(
      change_team(players, [0, 1, 0, 1], 1), choose_team(1, 0),
      change_team(players, [0, 0, 0, 1], 2), choose_team(0, 1),
      start_teams(players, [0, 0, 1, 1])
    ) { app.send(:start_new_game, row) }
    stored = assert_started(app, row, result, players, [0, 0, 1, 1])
    assignment = app.send(:game_definition, "axel_pong").team_assignment(JSON.parse(stored["options"]), players: players)
    assert(assignment.members_for(0) == players.first(2), "The human's manually chosen partner was not retained")
    assert(assignment.members_for(1) == players.last(2), "The opposing bot team was not retained")
    assert(app.notices.empty?, "A supported human/bot mix was rejected")
  end
end

test("the table owner may observe while four other humans play Doubles") do
  app = PongDoublesLobbyApp.new
  row = create_pong(app)
  app.lobby.set_observer(row, "Alice", true)
  players = %w[Bob Carol Dave Eve]
  players.each { |name| join(app, row, name) }
  result = with_forms(start_teams(players, [0, 1, 0, 1])) { app.send(:start_new_game, row) }
  assert_started(app, row, result, players, [0, 1, 0, 1])
  assert(app.notices.empty?, "An observing owner could not start the four actual players")
end

test("accepted teams survive game end, rematch and unrelated option editing") do
  app = PongDoublesLobbyApp.new
  row = create_pong(app)
  players = %w[Alice Bob Carol Dave]
  players.drop(1).each { |name| join(app, row, name) }
  accepted = with_forms(start_teams(players, [0, 1, 0, 1])) { app.send(:start_new_game, row) }
  first = assert_started(app, row, accepted, players, [0, 1, 0, 1])
  assert(app.transport.abort_game(first), 'Could not finish test match')
  saved = with_forms(lambda do |form|
    form.fields[3].index = 3 # difficulty: an unrelated setting
    form.accept_button.trigger(:press)
  end) { app.send(:change_table_game_options, row) }
  assert(saved, 'Could not edit waiting table settings')
  next_game = with_forms { app.send(:start_new_game, row) }
  assert(next_game && next_game['__id'] != first['__id'], 'Rematch needed another team dialog')
  assert(JSON.parse(next_game['options']).values_at('team_players', 'team_seats') == [players, [0, 1, 0, 1]], 'Rematch lost teams')
  assert(app.network_calls.count('Starting game') == 2, 'Accept or edit started an extra game')
end

test("custom point target uses the next field without moving focus or rebuilding the form") do
  app = PongDoublesLobbyApp.new
  game = GameRoomGames::AxelPong.new
  opened_form = nil
  result = with_forms(lambda do |form|
    opened_form = form
    assert_creation_form(form)
    target, custom = form.fields[5..6]
    assert(target.options == ["7", "11", "21", "Custom number", "Unlimited"], "Wrong target choices in real form")
    form.index = 5
    target.index = 3
    target.trigger(:move)
    assert(form.index == 5, "Selecting Custom number unexpectedly moved focus")
    visible = form.fields.reject { |field| form.hidden_controls.include?(field) }
    assert(visible[visible.index(target) + 1].equal?(custom), "Tab would skip the custom edit")
    custom.text = "31"
    target.index = 4
    target.trigger(:move)
    assert(form.hidden_controls.include?(custom) && form.index == 5, "Unlimited leaves the custom field visible or steals focus")
    target.index = 3
    target.trigger(:move)
    assert(custom.text == "31" && !form.hidden_controls.include?(custom), "Switching choices loses the custom value")
    form.accept_button.trigger(:press)
  end) { app.send(:configure_game_options, game, creating_table: true) }
  assert(result[:game_options]["target"] == "custom" && result[:game_options]["custom_target"] == 31, "Custom edit was not saved")
  options = JSON.parse(JSON.generate(result[:game_options]))
  row = app.lobby.create_table(name: "Custom Pong", game: "axel_pong", owner: "Alice", game_options: JSON.generate(options)).table
  join(app, row, "Bob")
  started = with_forms { app.send(:start_new_game, row) }
  stored = assert_started(app, row, started, %w[Alice Bob], nil)
  assert(game.points_to_win(JSON.parse(stored["options"])) == 31, "Starting a custom match lost its limit")
  assert(opened_form != nil && app.notices.empty?, "Custom target caused an unexpected error")
end

test("invalid custom input remains editable; Unlimited ignores its hidden value") do
  app = PongDoublesLobbyApp.new
  game = GameRoomGames::AxelPong.new
  first_form = nil
  steps = ["", "1", "1000"].each_with_index.map do |value, index|
    lambda do |form|
      first_form ||= form
      assert(form.equal?(first_form), "Validation recreated the form")
      target, custom = form.fields[5..6]
      assert(app.notices.length == index, "Invalid target was not rejected exactly once")
      target.index = 3
      target.trigger(:move)
      custom.text = value
      form.accept_button.trigger(:press)
    end
  end
  steps << lambda do |form|
    assert(form.equal?(first_form) && form.fields[6].text == "1000", "Validation lost the typed value")
    assert(app.notices.all? { |notice| notice == "Enter a whole number of points from 2 to 999." }, "Wrong target validation message")
    target = form.fields[5]
    target.index = 4
    target.trigger(:move)
    form.accept_button.trigger(:press)
  end
  result = with_forms(*steps) { app.send(:configure_game_options, game, creating_table: true) }
  assert(result[:game_options]["target"] == "unlimited", "Unlimited could not be saved after an invalid edit")
  edited = with_forms(lambda do |form|
    # Ctrl+X has no Private table field, so these indices are one lower.
    assert(form.fields[4].options[form.fields[4].index] == "Unlimited", "Editing an unlimited table resets its target")
    assert(form.hidden_controls.include?(form.fields[5]), "Ctrl+X shows a custom edit for Unlimited")
    form.accept_button.trigger(:press)
  end) { app.send(:configure_game_options, game, initial_options: result[:game_options]) }
  assert(edited["target"] == "unlimited", "Ctrl+X changed Unlimited")
end

end

PongDoublesLobbyTest.finish
