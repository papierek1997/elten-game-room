require_relative '../../support/french_tarot'

def finish_tarot_with_bonus(enabled)
  game = GameRoomGames::FrenchTarotTable.new
  env = GameRoomTest::PrivateSimulation.new_game(game: game, players: %w[Alice Bob Carol Dan],
    options: {'round_limit' => 1, 'petit_au_bout' => enabled}, seed: 2)
  FrenchTarotFixture.finish(env, contract: 'garde_sans')
  env
end

ordinary, bonus = [false, true].map { |enabled| finish_tarot_with_bonus(enabled) }
raise 'Wrong last trick winner' unless bonus.replay.state[:little_one_winner] == 'Bob'
before = ordinary.game.participant_scores(ordinary.replay)
after = bonus.game.participant_scores(bonus.replay)
delta = after.to_h { |player, score| [player, score - before.fetch(player)] }
raise 'Wrong independent bonus' unless delta == {'Alice' => -10, 'Bob' => 30, 'Carol' => -10, 'Dan' => -10}

progress = FrenchTarotFixture.match(rounds: 6)
4.times { raise unless progress.step(progress.legal_actions.find { |action| action['choice'] == 'pass' }) == :ok }
after_redeal = progress.replay
shortcut = progress.game.custom_game_shortcuts(after_redeal, progress.active_actor).find { |item| item.key == 'r' }
raise 'Redeal changed the announced deal number' unless shortcut&.message == 'Deal 1 of 6.'
raise 'Deal progress absent from history' unless after_redeal.history.any? { |entry| entry.text == shortcut.message }

puts 'PASS French Tarot last-trick bonus on/off, private replay, deal progress after all-pass'
