require_relative '../../../games/mahjong_support/bot'
own = [15,16,6,9,15,15,10,10,10,21,22,23,18,18]
available = [2,4,4,4,4,2,3,4,4,3,1,4,4,4,4,0,3,4,0,4,4,0,3,3,4,2,4,4,4,0,1,4,4,4]
before = Marshal.dump([own,available])
old = GameRoomMahjong::Bot::Efficiency.new(variant:'riichi',available:available,lookahead:false)
new = GameRoomMahjong::Bot::Efficiency.new(variant:'riichi',available:available)
prior = old.discard(own,[],own.uniq)
choice = new.discard(own,[],own.uniq)
raise 'Known one-away comparison no longer distinguishes paths' unless prior.kind==9 && choice.kind==16
chances = [prior,choice].map do |item|
  rest = own.dup
  rest.delete_at(rest.index(item.kind))
  new.send(:two_draw_value,rest,[],item.kind)
end
raise 'Two-draw refinement reduced its stated goal' unless chances[1]>chances[0]
raise 'Selective analysis changed the real hand/inventory' unless Marshal.dump([own,available])==before
raise 'Forced legal choice was lost' unless new.discard(own,[],[9]).kind==9
puts 'PASS Mahjong close one-away refinement, real hand forms, public availability, better two-draw finish chance, nonmutation'
