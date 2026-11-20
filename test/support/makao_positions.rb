require_relative 'new_games_fixture'

def makao_replay(state)
  GameRoomGames::Replay.new(
    players: state[:players], current_player: state[:current_player],
    winner: state[:winner], draw: false, state: state,
    accepted_events: [], history: []
  )
end

def playing_makao_state(game, players, options, current:, hands:, top:)
  state = game.send(:initial_state, players, game.normalize_options(options))
  state.update(
    phase: :playing,
    current_player: current,
    hands: hands,
    draw_pile: %w[2C 3C 4C 6C 8C TC QC AC],
    discard: [top],
    declared_suit: top[1],
    declared_rank: top[0]
  )
  state
end
