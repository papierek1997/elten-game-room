require_relative '../../support/duck_challenge_native'
FormTimer = EltenAPI::Controls::FormTimer unless Object.const_defined?(:FormTimer, false)
require_relative '../../support/manual_form_timer'
require_relative '../../../games/darts'
require_relative '../../../lib/darts/client'
require_relative '../../../lib/game_screen'
require_relative '../../../lib/game_history_view'

class DartsHistoryRepository
  def players_for(session); session.fetch('__players'); end
  def actor_of(event, _session); event.fetch('actor'); end
  def event_id(event); event.fetch('__id'); end
  def session_id(_session); 7; end
end

class DartsHistoryFeedback
  attr_accessor :values
  def initialize; @values = []; end
  def take_feedback; result, @values = @values, []; result; end
end

class DartsHistoryAudio
  def silence; end
end

class DartsHistoryMouse
  def suspend; [[], false]; end
end

class DartsHistoryLayout < Struct.new(:form, :surface, :history, :updates)
  def update_history(items)
    self.updates += 1
    history.replace_entries(items)
  end
end

DuckChallengeNativeDriver.new
game, repository, feedback = GameRoomGames::Darts.new, DartsHistoryRepository.new, DartsHistoryFeedback.new
preferences = {'private_records_in_history'=>true, 'mouse_input'=>false}
program = Object.new
program.define_singleton_method(:darts_preferences) { preferences }
session = {'__id'=>7, '__players'=>['Alice'], '__table_owner'=>'Alice',
  'options'=>JSON.generate(game.default_options.merge('rounds'=>1))}
events = [{'__id'=>1, '__insertion_user'=>'Alice', 'actor'=>'Alice', 'action'=>'darts_start', 'value'=>'a' * 32}]
3.times do |i|
  events << {'__id'=>i + 2, '__insertion_user'=>'Alice', 'actor'=>'Alice',
    'action'=>'darts_throw', 'value'=>"#{i}:700:0:500:m"}
end
replay = game.replay(session, events, repository)
client = GameRoomDarts::Client.new(program, game, audio:DartsHistoryAudio.new, mouse:DartsHistoryMouse.new,
  ranking_service:feedback, clock:-> { 0.0 })
client.before_wait(replay, 'Alice')
client.send(:refresh_preferences)
screen = GameScreen.allocate
{program:program, repository:repository, game:game, session:session, game_client:client,
  surface_state:{}, activity_repository:nil}.each { |key, value| screen.instance_variable_set("@#{key}", value) }
history = GameRoomHistory::View.new(header:'History')
history.replace_entries(screen.send(:combined_history_items, replay))
history.index, history.check = 2, 5
chat = EditBox.new('Chat', text:'Keep my draft.', quiet:true)
form = GameRoomUI::Form.new([history, chat], program:program, index:1, quiet:true)
layout = DartsHistoryLayout.new(form, nil, history, 0)
screen.instance_variable_set(:@layout, layout)
queue = Object.new
queue.define_singleton_method(:advance) { false }
presenter = Struct.new(:event_presentation).new(queue)
screen.define_singleton_method(:event_presenter) { presenter }
screen.define_singleton_method(:announce_due_timers) { |_replay| }
screen.define_singleton_method(:automatic_action_due?) { |_replay| false }
screen.define_singleton_method(:connection_recovery_pending?) { false }
sync = Object.new
sync.define_singleton_method(:next_event) { |**| nil }
screen.instance_variable_set(:@synchronizer, sync)
wait = GameScreen::WaitState.new(replay:replay, session:session, actor:'Alice')
screen.send(:bind_wait_timer, wait, layout, -> {})
timer = form.instance_variable_get(:@timers).last
timer.fire
baseline = layout.updates
selection = [history.index, history.check, form.index, chat.text]
feedback.values = [{'result_key'=>'a' * 64, 'user'=>'Alice', 'difficulty'=>'normal',
  'personal_record'=>{'score'=>271, 'time_ms'=>4321}, 'placements'=>[]}]
SpeechOutput.reset
client.frame(background:true)
assert(!history.items.any? { |text| text.include?('New personal') },
  'a background client frame mutated a native history control')
timer.fire
assert(history.items.last.include?('New personal three-dart record: 271 points'),
  'a confirmed late record did not reach the already open history')
assert([history.index, history.check, form.index, chat.text] == selection,
  'local history refresh changed the selection, focus or chat draft')
assert(layout.updates == baseline + 1 && wait.action.nil?, 'private history rebuilt or resumed the game form')
speech = SpeechOutput.calls.dup
10.times { timer.fire }
assert(layout.updates == baseline + 1 && SpeechOutput.calls == speech,
  'unchanged client frames refreshed or reread history')
preferences['private_records_in_history'] = false
client.send(:refresh_preferences)
timer.fire
assert(!history.items.any? { |text| text.include?('New personal') }, 'disabling private history left the entry displayed')
preferences['private_records_in_history'] = true
client.send(:refresh_preferences)
timer.fire
assert(history.items.count { |text| text.include?('New personal') } == 1,
  'reenabling private history lost or duplicated the confirmed record')
puts 'PASS Darts late private history: actual form timer, native text control, quiet refresh and retained focus/draft'
