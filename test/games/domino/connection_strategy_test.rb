require_relative '../../support/domino'
require_relative '../../../games/mexican_train'
tiles = GameRoomDominoTiles
own = %w[550 000 460 340 450 030 040]
opponent = (tiles.deck(6) - own - [tiles.tile(2, 4)]).first(7)
before = own.dup
assert(tiles.reachable(%w[120 230 340 550], [1]) == 3, 'Only directly matching tiles were counted')
assert(tiles.reachable(%w[120 230 340 550], [6]) == 0, 'Unconnected components counted as reachable')
assert(tiles.reachable(%w[121 120 230], [1]) == 3, 'Physical copies collapsed in the connection model')
assert(tiles.reachable(%w[120 130 140], [1]) == 3, 'Branch fixture lost its common component')
assert(tiles.playable_count(%w[120 130 140], [1]) == 1, 'A single end cannot follow three branches')
assert(tiles.playable_count(%w[120 130 140], [1,1]) == 2, 'Two ends cannot follow three branches')
assert(tiles.playable_count(%w[120 230 340], [1]) == 3, 'A real three-tile trail was missed')
assert(tiles.playable_count(%w[120 130 140], [1],limit:0) == 3, 'Exhausted analysis must use the old component bound')
%w[domino mexican_train].each do |id|
  game = id == 'domino' ? GameRoomGames::Domino.new : GameRoomGames::MexicanTrain.new
  state = position(game, {'A'=>own.dup, 'B'=>opponent.dup}, chain: chain(2, 4), stock: [], options: {'forbid_draw'=>true})
  if id == 'mexican_train'
    state[:trains] = {'p0'=>{owner:'A',end:2,open:false,chain:[]},
      'p1'=>{owner:'B',end:7,open:false,chain:[]}, 'm'=>{owner:nil,end:4,open:true,chain:[]}}
  end
  replay = replay_of(state)
  snapshot = Marshal.dump(state)
  actions = game.legal_actions(replay, 'A')
  choice = actions.max_by { |action| game.bot_action_score(replay, 'A', action) }
  assert(choice['tile'] == '340', "#{id}: losing the 3-0/0-4 bridge for immediate pips")
  assert(Marshal.dump(state) == snapshot && own == before, "#{id}: evaluating connections changed ownership")
  assert(move(game, state, 'play', tile: choice['tile'], target: choice['target']).first == :ok,
    "#{id}: new preference cannot pass the production rules")
end
puts 'PASS Domino/Mexican Train component planning, physical copies, bridge preservation, real move acceptance and nonmutation'
