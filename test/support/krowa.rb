# Small deterministic fixtures: no network, profiles or live client.
require "json"
require_relative "hidden_submission_files"
def _(text); text; end
require_relative "../../games/krowa"
require_relative "../../lib/game_random"

def assert(value, message); raise message unless value; end

class KrowaTestProgram < HiddenSubmissionFiles
  attr_accessor :fail_write
  attr_reader :files, :writes
  def initialize; super; @files = {}; @writes = 0; end
  def before_hidden_write(_name)
    raise IOError, "test disk unavailable" if fail_write
    @writes += 1
  end
  def read_json(path, default:); Marshal.load(Marshal.dump(@files.fetch(path, default))); end
  def write_json(path, data)
    raise IOError, "test disk unavailable" if fail_write
    @writes += 1
    @files[path] = Marshal.load(Marshal.dump(data))
    true
  end
  def update_json(path, default:)
    data = read_json(path, default: default)
    yield data
    write_json(path, data)
    data
  end
end

class KrowaTestRepository
  def initialize(players); @players = players; end
  def players_for(_session); @players; end
  def actor_of(event, _session); event.fetch("actor"); end
  def event_id(event); event["id"] || event["__id"]; end
  def session_id(session); session["__id"]; end
end

class KrowaTestRandom
  Roll = Struct.new(:values)
  def roll(count:, sides:); Roll.new(Array.new(count, 1)); end
end

class KrowaTestGame
  attr_reader :game, :bank, :session, :events, :repository, :context, :program
  def initialize(variant: "random", players: ["Alice"], scoring: "attempts", program: KrowaTestProgram.new)
    @program = program
    @bank = GameRoomGames::KrowaWordBank.new(GameRoomKrowa::WordRepository.new(%w[kot las dom rak sok mat koza krowa palacz kwiatek krokodyl telewizor]))
    @game = GameRoomGames::Krowa.new(bank: @bank)
    options = @game.default_options.merge("variant" => variant, "length" => 3, "race_scoring" => scoring)
    if variant == "daily"
      options.merge!("__daily_day" => "2026-09-18", "__daily_assignment" => @bank.new_daily_assignment("2026-09-18"))
    end
    @session = {"__id" => 10, "table_id" => 2, "created_at" => 1_800_000_000,
      "options" => JSON.generate(options)}
    @repository = KrowaTestRepository.new(players)
    @events = []
    @context = GameRoomGames::ActionContext.new(session_id: 10, table_id: 2, table_owner: "Alice",
      hidden_submissions: HiddenSubmissions::Vault.new(program.storage),
      random_source: KrowaTestRandom.new, now: 1_800_000_000.0, local_data: {"daily_day" => "2026-09-18"})
  end
  def replay; @game.replay(@session, @events, @repository); end
  def action(actor, selection)
    status, plan = @game.action_for(selection, replay, actor, context: @context)
    return status unless status == :ok
    plan.events.each do |command|
      id = @events.length + 1
      @events << {"id" => id, "sequence" => id, "actor" => actor, "action" => command.action,
        "value" => command.value, "created_at" => @context.now.to_i}
    end
    assert(replay.accepted_events.length == @events.length, "Krowa fixture replay rejected #{selection}")
    :ok
  end
  def automatic
    selection = @game.automatic_action(replay, "Alice", context: @context)
    selection && action("Alice", selection)
  end
  def guess(actor, word, adding: false)
    action(actor, "kind" => "question", "action" => adding ? "add_word" : "submit",
      "question_id" => "krowa-answer-#{replay.state[:round]}", "answer" => word)
  end
  def surrender(actor); action(actor, "kind" => "command", "action" => "surrender"); end
end
