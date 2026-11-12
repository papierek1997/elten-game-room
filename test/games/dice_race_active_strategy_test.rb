require_relative '../../games/farkle'
require_relative '../../games/cat_head_tail'

class DiceRaceFixture
  Repository = Struct.new(:players) do
    def players_for(_session); players; end
    def actor_of(event, _session = nil); event.fetch('actor'); end
    def event_id(event); event.fetch('id'); end
  end
  attr_reader :game, :players, :repository, :session, :events, :replay

  def initialize(game, options)
    @game, @players, @events = game, %w[Alice Bob Carol Dave], []
    @repository = Repository.new(players)
    @session = { 'options' => JSON.generate(game.new_game_options(options)) }
  end

  def append(actor, action, value = '', **markers)
    event = { 'id' => events.size + 1, 'actor' => actor, 'action' => action, 'value' => value }.merge(markers.transform_keys(&:to_s))
    result = game.replay(session, events + [event], repository)
    raise 'Model fixture rejected an ordinary action/boundary' unless result.accepted_events == events + [event]
    @events << event
    @replay = result
  end

  def eliminate(seat)
    # Only the internal, already-validated boundary projection carries this
    # flag. This fixture does not test native authorization or act on a server.
    append('Alice', 'tournament_elimination', JSON.generate([seat]), __tournament_elimination: true, __controller: true)
  end

  def choice(replay = @replay)
    game.bot_strategy.choose(actions: game.legal_actions(replay, replay.current_player), actor: replay.current_player,
      random_source: nil, game: game, replay: replay)
  end
end

fixture = DiceRaceFixture.new(GameRoomGames::Farkle.new, 'score_limit' => 100, 'turn_minimum' => 0, 'entry_minimum' => 0)
fixture.eliminate(3)
[['Alice', 'roll', '1,2,3,4,5,6'], ['Alice', 'keep', '0,1,2,3,4,5'], ['Alice', 'bank'],
  ['Bob', 'roll', '2,2,3,3,4,6'], ['Carol', 'roll', '1,2,3,4,5,6'], ['Carol', 'keep', '0,1,2,3,4']].each { |row| fixture.append(*row) }
raise 'Farkle banks a certain loss by counting a removed final seat' unless fixture.choice['action'] == 'roll'
[['Carol', 'roll', '1'], ['Carol', 'keep', '0'], ['Carol', 'roll', '1,2,3,4,5,6'],
  ['Carol', 'keep', '0,1,2,3,4,5'], ['Carol', 'bank']].each { |row| fixture.append(*row) }
raise 'Farkle selected a purported winning line with no real chance of winning' unless fixture.replay.finished? && fixture.replay.winner == 'Carol'

fixture = DiceRaceFixture.new(GameRoomGames::CatHeadTail.new, 'score_limit' => 10)
8.times { fixture.append('Alice', 'roll', '2') }
fixture.eliminate(0)
[['Bob', 'roll', '6'], ['Bob', 'roll', '6'], ['Bob', 'bank'], ['Carol', 'bank'],
  ['Dave', 'roll', '6'], ['Dave', 'roll', '4'], ['Dave', 'roll', '4']].each { |row| fixture.append(*row) }
raise 'Cat risks a guaranteed win because a removed player has a higher score' unless fixture.choice['action'] == 'bank'
changed = Marshal.load(Marshal.dump(fixture.replay))
changed.state[:scores]['Alice'] = 0
raise 'An irrelevant removed score still changes the decision' unless fixture.choice(changed) == fixture.choice
fixture.append('Dave', 'bank')
raise 'Cat guaranteed-win bank does not match settlement' unless fixture.replay.finished? && fixture.replay.winner == 'Dave'

raise 'Roster filtering changed order/case semantics' unless GameRoomParticipants.excluding(%w[Alice Bob Carol], ['bOb']) == %w[Alice Carol]
puts 'PASS active-roster dice strategies: last active seat, removed leaders, real final outcomes and case-insensitive identity filtering'
