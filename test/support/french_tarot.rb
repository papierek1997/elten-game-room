require_relative 'private_simulation'
require_relative '../../games/french_tarot_support/french_tarot_table'
module FrenchTarotFixture
  module_function
  def match(rounds: 1, seed: 41)
    GameRoomTest::PrivateSimulation.new_game(game: GameRoomGames::FrenchTarotTable.new,
      players: %w[Alice Bob Carol Dan], options: {'round_limit'=>rounds}, seed: seed)
  end
  def finish(env, contract:)
    1000.times do
      return if env.finished?
      actions = env.legal_actions
      choice = env.replay.state[:phase] == :bidding && env.replay.state[:bid_count].zero? ? contract : 'pass'
      action = env.replay.state[:phase] == :bidding ? actions.find { |item| item['choice'] == choice } : actions.first
      raise 'Production round has no action' unless action
      raise 'Production move was refused' unless env.step(action) == :ok
    end
    raise 'Production round failed to finish'
  end
end
