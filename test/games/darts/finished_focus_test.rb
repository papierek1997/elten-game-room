# encoding: UTF-8
require_relative '../../support/assertions'
require_relative '../../support/ui'
require_relative '../../../games/darts'
require_relative '../../../lib/game_surfaces'
require_relative '../../../lib/game_screen'

include GameRoomTest::Assertions

module Session
  def self.name; 'Alice'; end
end

class DartsFinishedFocusRepository
  def players_for(session); session.fetch('__players'); end
  def actor_of(event, _session); event.fetch('actor'); end
  def event_id(event); event.fetch('__id'); end
  def session_id(_session); 7; end
end

class DartsFinishedFocusClient
  attr_accessor :pending
  def presentation_pending?; pending == true; end
  def context_data; {}; end
end

game = GameRoomGames::Darts.new
repository = DartsFinishedFocusRepository.new
session = {'__id'=>7, '__players'=>['Alice'], '__table_owner'=>'Alice',
  'options'=>JSON.generate(game.default_options.merge('rounds'=>1))}
start = {'__id'=>1, '__insertion_user'=>'Alice', 'actor'=>'Alice', 'action'=>'darts_start', 'value'=>'a' * 32}
throws = 3.times.map do |index|
  {'__id'=>index + 2, '__insertion_user'=>'Alice', 'actor'=>'Alice', 'action'=>'darts_throw',
    'value'=>"#{index}:700:0:500:m"}
end

screen = GameScreen.allocate
{
  program: Object.new, repository: repository, game: game, session: session,
  table: {'__id'=>4}, table_owner: 'Alice', game_services: {}, activity_repository: nil,
  game_name: ->(id) { id.to_s }, presentation_ui_thread: Thread.current
}.each { |key, value| screen.instance_variable_set("@#{key}", value) }
screen.send(:initialize_view_state)
screen.instance_variable_set(:@hidden_submissions, nil)
screen.instance_variable_set(:@random_source, nil)
client = DartsFinishedFocusClient.new
screen.instance_variable_set(:@game_client, client)

active = game.replay(session, [start, *throws.first(2)], repository)
screen.send(:prepare_action_view, active)

client.pending = true
finished = game.replay(session, [start, *throws], repository)
deferred = screen.send(:prepare_action_view, finished)
assert(deferred.announce_finished_focus && deferred.defer_finished_focus,
  'finished Darts view did not defer focus while its audible result was pending')
assert(!deferred.layout.form.fields.include?(deferred.layout.restart_button),
  'Restart game appeared before the Darts result presentation finished')

client.pending = false
ready = screen.send(:prepare_action_view, finished)
assert(ready.announce_finished_focus && !ready.defer_finished_focus,
  'Restart game was not queued for focus after the Darts result presentation')
assert(ready.layout.form.fields.include?(ready.layout.restart_button),
  'Restart game did not appear after the Darts result presentation finished')
assert(ready.layout.surface == nil, 'finished Darts unexpectedly retained a playfield')
wait = GameScreen::WaitState.new(replay: finished, session: session, actor: 'Alice')
screen.send(:bind_wait_surface, wait, ready.layout, -> {})
ready.layout.back_button.trigger(:press)
assert(wait.action == :back, 'a finished Darts screen without a playfield could not be left')

puts 'PASS Darts finished focus: result completes before Restart, and a surface-free finished view remains usable'
