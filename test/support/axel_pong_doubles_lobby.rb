require_relative "ui"
require_relative "log"
require_relative "native_live_sessions"

class Program
  def self.server_app(**_options); end
  def self.app_runtime; nil; end
end

class Static < FakeControl
  attr_reader :text

  def initialize(text)
    super()
    @text = text
  end

  def focus(*_arguments); end
end

class CheckBox < FakeControl
  attr_accessor :checked

  def initialize(header, checked: false)
    super()
    @header, @checked = header, checked
  end

  def focus(*_arguments); end
end

class EditBox
  Flags::Numbers = 8 unless Flags.const_defined?(:Numbers)

  def select_all
    @check = 0
    @index = @text.length
  end
end

class Form
  class << self
    attr_accessor :pong_steps
  end

  alias wait_without_pong_lobby_driver wait

  def wait
    wait_without_pong_lobby_driver
    @pong_resumed = false
    until @pong_resumed
      step = Form.pong_steps&.shift
      raise "Unexpected form or exhausted UI script: #{fields.map(&:header).inspect}" unless step

      step.call(self)
    end
  end

  def resume
    @pong_resumed = true
  end
end

require_relative "../../__app"

class PongDoublesLobbyApp < EltenGameRoom
  attr_reader :broker, :transport, :lobby, :games, :notices, :opened_tables, :network_calls

  def self.announce_new_public_table(_table); end

  def initialize
    $game_room_test_user = "Alice"
    @broker = NativeLiveSessionsBroker.new
    program = ProgramDouble.new(@broker.endpoint("Alice"))
    @server_tables = {}
    @transport = GameRoomTransport.new(program)
    @lobby = LobbyRepository.new(program, transport: @transport, server_tables: @server_tables)
    @games = GameRepository.new(program, transport: @transport, server_tables: @server_tables)
    @table_activity = TableActivityRepository.new(server_tables: @server_tables, transport: @transport)
    @notices, @opened_tables, @network_calls = [], [], []
  end

  def read_json(_path, default:); default; end
  def alert(message); @notices << message; end
  def play_game_sound(_name); end
  def show_table_screen(table); @opened_tables << table; end

  def run_network_task(title, **_options)
    @network_calls << title
    yield
  end
end

module PongDoublesLobbyTest
  extend self

  def with_forms(*steps)
    raise "Nested UI scripts are not supported" if Form.pong_steps

    Form.pong_steps = steps
    result = yield
    assert(Form.pong_steps.empty?, "The UI returned before all scripted interactions were exercised")
    result
  ensure
    Form.pong_steps = nil
  end

  def button(form, label)
    found = form.fields.find { |field| field.is_a?(Button) && field.label == label }
    assert(found != nil, "The form lost its #{label} button")
    found
  end

  def assert_creation_form(form)
    assert(form.is_a?(GameRoomUI::Form), "Creation bypassed the shared Game Room form")
    assert(form.index == 0 && form.fields.first.is_a?(Static), "Creation skipped its opening instructions")
    assert(form.fields.first.text.start_with?("Choose game options"), "Creation lost its instructions")
    assert(form.fields[1..5].map(&:header) == [
      "Private table", "Game mode", "Match type",
      "Difficulty and ball speed", "Points to win"
    ], "Single/Doubles was not immediately after Game mode in the actual creation form")
    privacy, arcade, mode, difficulty, target = form.fields[1..5]
    assert(privacy.is_a?(CheckBox) && !privacy.checked, "New tables stopped defaulting to public")
    assert(arcade.is_a?(ListBox) && arcade.options == ["Classic", "Arcade"] && arcade.index == 0, "Game mode stopped defaulting to Classic")
    assert(mode.is_a?(ListBox) && mode.options == ["Single", "Doubles"], "Match type is not a Single/Doubles list")
    assert(mode.index == 0, "Single was not initially selected")
    assert(difficulty.options[difficulty.index] == "Normal", "Match type changed the default difficulty")
    assert(target.options[target.index] == "11", "Match type changed the default target")
    assert(form.hidden_controls == [form.fields[6], form.fields[8]] &&
      form.hidden_controls.all? { |field| field.is_a?(EditBox) }, "Creation must hide the custom point target and disabled P2P limit")
    assert(form.accept_button == button(form, "Create table"), "Creation has the wrong default action")
    assert(form.cancel_button == button(form, "Cancel"), "Creation lost Cancel")
  end

  def create_pong(app, mode: "Doubles", cancel: false)
    with_forms(
      lambda do |form|
        games = form.fields.first
        assert(games.header == "Create a new table", "Creation bypassed real game selection")
        games.index = games.options.index("Axel Pong")
        assert(games.index != nil, "Axel Pong is missing from the real game selector")
        form.accept_button.trigger(:press)
      end,
      lambda do |form|
        assert_creation_form(form)
        match_type = form.fields[3]
        match_type.index = match_type.options.index(mode)
        match_type.trigger(:move)
        assert(match_type.options[match_type.index] == mode, "Changing match type reset the selection")
        (cancel ? form.cancel_button : form.accept_button).trigger(:press)
      end
    ) { app.send(:show_create_table) }
    return nil if cancel

    assert(app.opened_tables.length == 1, "Creation did not open exactly one table")
    row = app.opened_tables.first
    stored = app.lobby.snapshot_for(row, force: true).table
    options = JSON.parse(stored.fetch("game_options"))
    expected = {"arcade" => false, "team_size" => mode == "Doubles" ? 2 : 0, "difficulty" => 2, "target" => 11, "custom_target" => 11,
      "p2p_enabled" => false, "p2p_participants_limit" => 8}
    assert(options == expected, "The actual creation form did not persist its selected match type and defaults")
    assert_no_game(app, stored)
    stored
  end

  def as_user(name)
    previous = Thread.current[:game_room_test_user]
    Thread.current[:game_room_test_user] = name
    yield
  ensure
    Thread.current[:game_room_test_user] = previous
  end

  def join(app, row, user, observer: false)
    as_user(user) do
      program = ProgramDouble.new(app.broker.endpoint(user))
      transport = GameRoomTransport.new(program)
      selected = transport.discover_rooms.find { |table| table["__id"] == row["__id"] }
      assert(selected != nil, "#{user} could not discover the test table")
      joined = transport.establish_membership(table_id: row["__id"], owner: "Alice", capacity: 8, user: user, table: selected)
      assert(joined, "#{user} could not join the test table")
      lobby = LobbyRepository.new(program, transport: transport, server_tables: {})
      if observer
        room = lobby.set_observer(row, user, true)
        assert(room.observer?(user), "#{user} did not become an observer")
      end
      GameRepository.new(program, transport: transport, server_tables: {})
    end
  end

  def team_form(form, players, seats)
    assert(form.fields.map { |field| field.is_a?(Button) ? field.label : field.header } == [
      "Players and teams", "Choose teams randomly", "Accept teams", "Change team", "Cancel"
    ], "Doubles bypassed or changed the shared team selector")
    assert(form.hidden_controls == [button(form, "Change team"), button(form, "Cancel")], "Tab includes hidden team commands")
    labels = players.each_with_index.map do |player, index|
      "#{GameRoomParticipants.display_name(player)}, team #{seats[index] + 1}"
    end
    assert(form.fields.first.options == labels, "Team choices lost the roster, included observers, or used the wrong seats")
    assert(form.accept_button == button(form, "Change team"), "Enter starts a game instead of changing the selected team")
    assert(form.cancel_button == button(form, "Cancel"), "Team selection lost Cancel")
    form.fields.first
  end

  def change_team(players, seats, player_index)
    lambda do |form|
      team_form(form, players, seats).index = player_index
      form.accept_button.trigger(:press)
    end
  end

  def choose_team(current, selected)
    lambda do |form|
      list = form.fields.first
      assert(list.header == "Choose a team" && list.options == ["Team 1", "Team 2"], "Manual selection bypassed the real team chooser")
      assert(list.index == current, "Team chooser lost the selected player's current team")
      list.index = selected
      form.accept_button.trigger(:press)
    end
  end

  def start_teams(players, seats)
    lambda do |form|
      team_form(form, players, seats)
      button(form, "Accept teams").trigger(:press)
    end
  end

  def start_records(app)
    app.broker.cores.values.flat_map(&:entries).select { |entry| entry.dig("packet", "kind") == "game_started" }
  end

  def assert_no_game(app, row)
    assert(app.games.session_for_table(row, force: true) == nil, "A rejected or cancelled start wrote a session")
    assert(start_records(app).empty?, "A rejected or cancelled start pushed a game_started record")
    assert(app.lobby.snapshot_for(row, force: true).table["status"] == "waiting", "A rejected or cancelled start marked the table playing")
  end

  def assert_started(app, row, result, players, seats)
    if seats && result == nil
      assert_no_game(app, row)
      chosen = JSON.parse(app.lobby.snapshot_for(row, force: true).table.fetch("game_options"))
      assert(chosen["team_players"] == players && chosen["team_seats"] == seats, "Accept did not persist the line-up in the room")
      result = with_forms { app.send(:start_new_game, row) }
    end
    stored = app.games.session_for_table(row, force: true)
    assert(result != nil && stored != nil && result["__id"] == stored["__id"], "Start did not return the session read back from storage")
    assert(start_records(app).length == 1, "Start did not persist exactly one session")
    assert(app.games.players_for(stored) == players, "The persisted player roster changed or contains an observer")
    options = JSON.parse(stored.fetch("options"))
    assert(options["team_seats"] == seats, "Chosen team seats were lost when the session was persisted")
    assert(app.lobby.snapshot_for(row, force: true).table["status"] == "playing", "Successful start left the table waiting")
    game = app.send(:game_definition, "axel_pong")
    snapshot = app.games.snapshot_for(stored, force_events: true)
    replay = game.replay(snapshot.session, snapshot.events, app.games)
    assert(replay.players == players && replay.state[:options]["team_seats"] == seats, "Replay did not restore the session's chosen roster and teams")
    assert(game.validation_error(options, player_count: players.length) == nil, "A started session has invalid options")
    stored
  end

  @passed = 0
  @failures = []

  def test(name)
    yield
    @passed += 1
    puts "PASS #{name}"
  rescue StandardError => error
    @failures << name
    warn "FAIL #{name}: #{error.class}: #{error.message}"
    warn error.backtrace.first(6).join("\n")
  end

  def finish
    puts "Pong doubles lobby: #{@passed} passed, #{@failures.length} failed"
    exit(1) unless @failures.empty?
  end
end
