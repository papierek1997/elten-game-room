require_relative '../support/settings_widget'
require_relative '../support/assertions'
require_relative '../../lib/game_background_presentation'
include GameRoomTest::Assertions

module EltenAPI::UI
  def loop_update; :native; end
end
scene=Object.new.extend(EltenAPI::UI)
program_class=Class.new do
  extend GameRoomTournaments::ServerCoordinationRuntime
end
program=program_class.new
coordinator=Object.new
ticks=[]
coordinator.define_singleton_method(:tick){ticks << Thread.current}
coordinator.define_singleton_method(:last_error){nil}
coordinator.define_singleton_method(:take_observed_references){[]}
coordinator.define_singleton_method(:close){}
previous_account=Session.instance_variable_get(:@name)
previous_token=Session.token
Session.name=Session.name
Session.token='covered-coordination-fixture'
program_class.instance_variable_set(:@tournament_runtime_program,program)
program_class.instance_variable_set(:@tournament_runtime_account,Session.name.downcase)
program_class.instance_variable_set(:@tournament_coordinator,coordinator)
covered=true
runner=Object.new
runner.define_singleton_method(:covered?){covered}
runner.define_singleton_method(:closed?){false}
screen=Object.new
presentations=0
screen.define_singleton_method(:present_background_session){|_|presentations+=1}
registration=GameRoomBackgroundPresentation.attach(screen,program:program,runner:runner,key:[:lease])
$mainthread=$currentthread=Thread.current
begin
  Thread.new do
    $currentthread=Thread.current
    5.times{assert_equal(:native,scene.send(:loop_update))}
    assert_equal([Thread.current],ticks,'Covered native window did not pump coordination once')
    assert_equal(5,presentations,'Coordination throttled game presentation')
    program_class.tournament_coordination_tick
    assert_equal(1,ticks.size,'Foreground/background pumps doubled coordination')
    sleep 1.05
    scene.send(:loop_update)
    assert_equal(2,ticks.size,'Covered pump stopped after its first tick')
    covered=false
    sleep 1.05
    scene.send(:loop_update)
    assert_equal(2,ticks.size,'Visible screen was pumped through the covered bridge')
    program_class.tournament_coordination_tick
    assert_equal(3,ticks.size,'Foreground extension did not resume normal coordination')
    registration.close
    covered=true
    sleep 1.05
    scene.send(:loop_update)
    assert_equal(3,ticks.size,'Closed presenter retained background work')
  ensure
    $currentthread=$mainthread
  end.value
ensure
  registration.close
  program_class.stop_tournament_coordination
  Session.name=previous_account
  Session.token=previous_token
end
puts 'PASS covered tournament coordination: active UI, one shared cadence, foreground return and presenter cleanup'
