require_relative '../../support/session_runner'
require_relative '../../../games/mania_pisania'
require_relative '../../../lib/mania_pisania/practice'

game = GameRoomGames::ManiaPisania.new
h = NativeRoomHarness.new(game:game,users:%w[Alice Bob],options:{'variant'=>'words','word_language'=>'en'})
h.start
h.add_client('Watcher'); h.join('Watcher')
h.as('Alice') do
  h.transports['Alice'].set_observer(h.table,true,actor:'Alice',subject:'Watcher')
  h.transports['Alice'].transfer_room_owner(h.table,'Watcher')
end
runners = %w[Alice Bob Watcher].to_h { |name| [name,runner_for(h,name)] }
publish = ->(name,data) do
  h.as(name) do
    runners.fetch(name).publish_view(session:h.session,replay:h.replay(name),busy:false,
      context:GameRoomGames::ActionContext.new(local_data:data))
  end
end
begin
  step(h,runners['Watcher'],'Watcher',count:3)
  replay = h.replay('Watcher')
  assert(replay.state[:phase] == :active && replay.players == %w[Alice Bob], 'An observing host could not start without becoming a player')
  save_id = 'abc123' * 5 + '00'
  request = {'action'=>'save_begin','save_id'=>save_id,'round'=>replay.state[:round],'owner'=>'Watcher'}
  publish.call('Watcher',{'typing_save_action'=>request})
  step(h,runners['Watcher'],'Watcher',count:3)
  assert(h.replay('Watcher').state.dig(:saving,:id) == save_id, 'An observing host could not request a save through the runner')
  %w[Alice Bob].each do |name|
    replay = h.replay(name)
    practice = GameRoomTyping::Practice.new(options:replay.state[:options],
      word_bank:GameRoomTyping::WordBank.for_options(replay.state[:options]),seed:replay.state[:seed],multiplayer:true)
    practice.start; practice.pause
    publish.call(name,{'typing_checkpoint'=>practice.snapshot})
    step(h,runners[name],name,count:3)
  end
  assert(game.save_ready?(h.replay('Watcher')), 'Both private local practices did not acknowledge their multiplayer checkpoints')
  request = request.merge('action'=>'save_cancel')
  publish.call('Watcher',{'typing_save_action'=>request})
  step(h,runners['Watcher'],'Watcher',count:3)
  assert(h.replay('Watcher').state[:saving].nil?, 'An observing host could not resume after cancelling the save')
  %w[Alice Bob Watcher].each { |name| publish.call(name,{}) }
  runners['Alice'].close
  h.as('Alice') { h.transports['Alice'].deactivate_table(table_id:h.table['__id']) }
  step(h,runners['Watcher'],'Watcher',count:2)
  assert(h.transports['Watcher'].room_snapshot(h.table)[:bots].empty?, 'A no-bot game created a replacement bot')
  h.join('Alice')
  runners['Alice'] = runner_for(h,'Alice')
  %w[Alice Bob].each_with_index do |name,index|
    replay = h.replay(name)
    result = {'words'=>10-index,'errors'=>index,'levels'=>0,'elapsed_ms'=>12000,'wpm'=>50.0-index,'assisted'=>false}
    # Like the live typing client, publish the completed local result to the
    # runner. It re-reads native control epochs after the leave/return above.
    publish.call(name,{'typing_result'=>{'round'=>replay.state[:round],'result'=>result}})
    step(h,runners[name],name,count:3)
  end
  h.assert_converged('Typing: observing host, save/cancel, no-bot return and results')
  assert(h.replay('Watcher').finished? && h.replay('Watcher').winner == 'Alice', 'The restored human seat could not finish typing')
ensure
  runners.each_value(&:close)
end
puts 'PASS typing native runner: spectator host, authenticated moderator start/save/cancel, two checkpoints, no bot replacement, player return and converged completion'
