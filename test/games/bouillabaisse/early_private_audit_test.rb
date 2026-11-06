require_relative '../../support/private_card_games'
require_relative '../../../games/bouillabaisse'

game = GameRoomGames::Bouillabaisse.new
h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob Carol])
begin
  51.times do
    actor = h.replay('Alice').current_player
    PrivateCardGamesTest.submit(h, runners, actor, game.legal_actions(h.replay(actor), actor).first)
  end
  16.times do
    break if h.replay('Alice').state[:round] == 2 && h.replay('Alice').state[:phase] == :playing
    PrivateCardGamesTest.tick(h, runners)
  end
  before = h.replay('Alice')
  assert(before.state[:round] == 2 && before.state[:phase] == :playing, 'second round did not start')
  scores = before.state[:scores].dup
  score_entries = before.history.count { |entry| entry.kind == :score }
  injected = false
  51.times do
    replay = h.replay('Alice')
    break unless replay.state[:phase] == :playing
    actor = replay.current_player
    mine = h.replay(actor)
    legal = game.legal_actions(mine, actor)
    off = mine.state[:hands][actor].find { |card| legal.none? { |action| action['card'] == card } }
    if off && !injected
      receipt = GameRoomPrivateCardLedger.locate(mine.state, actor, off)
      h.write(actor, [GameRoomPrivateCards.command('play', off, **receipt.merge(operation: 'reveal'))])
      injected = true
    else
      PrivateCardGamesTest.submit(h, runners, actor, legal.first)
    end
  end
  pending = h.replay('Alice')
  assert(injected && pending.state[:phase] == :private_show, 'early-end hidden-hand audit was not exercised')
  assert(pending.state[:scores] == scores, 'score was accepted before proving the unplayed hand')
  16.times do
    break unless h.replay('Alice').state[:phase] == :private_show
    PrivateCardGamesTest.tick(h, runners)
  end
  h.users.each do |user|
    replay = h.replay(user)
    assert(replay.state[:private_error] == :invalid_round && replay.state[:scores] == scores, 'early end accepted a proven follow-suit violation')
    assert(replay.history.count { |entry| entry.kind == :score } == score_entries, 'unaudited score entered history')
    assert(game.tournament_scored_checkpoint(replay, options: game.default_options) == {'status' => 'unsupported'}, 'bad round reached tournament standings')
  end
  puts 'PASS Bouillabaisse early private audit: unplayed cards prove a revoke before score or tournament publication'
ensure
  runners.each_value(&:close)
end
