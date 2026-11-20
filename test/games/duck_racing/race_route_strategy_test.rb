require_relative '../../../games/duck_racing_support/bots'
view = {seat:0,laps:3,hand:[],traps:{},racers:{
  0=>{progress:0,feathers:10,card_count:3,die_sides:6,die_rolls:0,frozen_turns:0,skip_turns:0},
  1=>{progress:5,feathers:10,card_count:3,die_sides:6,die_rolls:0,frozen_turns:0,skip_turns:0}}}
evaluate = -> { GameRoomDuckRacing::RaceEvaluation.new(view) }
ordinary = evaluate.call.send(:movement,0,2)
view[:traps][3] = {owner:0,type:'mine'}
raise 'A harmful own trap was incorrectly treated as harmless' unless evaluate.call.send(:movement,0,2)==ordinary-15
view[:traps][3] = {owner:0,type:'tar_stain'}
raise 'Own feather-stealing trap must remain inactive' unless evaluate.call.send(:movement,0,2)==ordinary
view[:traps].clear
value = evaluate.call.send(:movement,0,18)
expected = 18+0.6*(0.8+0.8-3.5)
raise 'Known independent 60% field effects were ignored' unless (value-expected).abs<1e-9
puts 'PASS Duck Racing public own-trap exception and expected known chance-field value without random draws'
