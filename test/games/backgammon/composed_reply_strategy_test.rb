require_relative '../../../games/backgammon'
board = [{11=>1,0=>14},{24=>1,0=>14}]
before = Marshal.dump(board)
risk = GameRoomGames::BackgammonBot.blot_risk(board,0)
raise 'Composed 4+6,6+4 and double-five hits are missing' unless (risk-3.0/36).abs<1e-12
raise 'Reply analysis mutated public board' unless before==Marshal.dump(board)
swapped = board.reverse
raise 'Second seat gets a different risk' unless (GameRoomGames::BackgammonBot.blot_risk(swapped,1)-risk).abs<1e-12
puts 'PASS Backgammon composed two-dice/double replies, both seats and nonmutation'
