require 'timeout'
require_relative 'support/table_watch_runtime'

class FormTimer
  def initialize(*_args, **_kwargs, &block); @callback = block; end
  def update; @callback.call; end
end
class Form
  class << self; attr_accessor :background_settings_driver; end
  def wait; Form.background_settings_driver.call(self); end
end
GameRoomClock.define_singleton_method(:synchronize) { true }
receiver = GameRoomTableWatch::Receiver.new(user: 'Alice', games: ['uno', 'makao'],
  uuid: EltenGameRoom.server_app_uuid, clock: -> { 2_000_000_000 })
receiver.games = ['uno']
EltenGameRoom.instance_variable_set(:@table_watch_receiver, receiver)
EltenGameRoom.instance_variable_set(:@table_watch_loader, nil)
EltenGameRoom.instance_variable_set(:@table_watch_load_state, nil)
arrived, release = Queue.new, Queue.new
calls = 0
answer, error = ['makao'], nil
repository = Object.new
repository.define_singleton_method(:load) do |_user|
  calls += 1
  arrived << true
  release.pop
  raise error if error
  answer
end
EltenGameRoom.define_singleton_method(:table_watch_repository) { repository }
values = GameRoomPreferences.defaults(EltenGameRoom::GAME_REGISTRY.ids)
games = [{ id: 'uno', name: 'UNO' }, { id: 'makao', name: 'Makao' }]
form_after_close = nil
begin
  EltenGameRoom.table_watch_start(refresh: true)
  work = EltenGameRoom.instance_variable_get(:@table_watch_loader)
  Timeout.timeout(3) { arrived.pop }
  EltenGameRoom.table_watch_start(refresh: true)
  assert(EltenGameRoom.instance_variable_get(:@table_watch_loader).equal?(work), 'Settings duplicated the startup read')
  Form.background_settings_driver = lambda do |form|
    form_after_close = form
    form.instance_variable_get(:@timers).each(&:update)
    loading = form.fields.find { |field| field.is_a?(EditBox) && field.header.start_with?('Notify me') }
    assert(loading.text == 'Loading notification settings', 'Pending read looks empty or inaccessible')
    form.fields.find { |field| field.header == 'Game sounds' }.index = 37
    form.accept_button.trigger(:press)
  end
  screen = GameRoomScreens::Settings.new(values, games: games, table_watch_available: false,
    table_watch_loader: -> { EltenGameRoom.table_watch_preferences_snapshot })
  updated = Timeout.timeout(0.25) { screen.wait }
  assert(updated['sound_volumes']['game'] == 37 && !updated.key?('table_watch_games') &&
    screen.table_watch_baseline.nil?, 'Saving local settings overwrote unresolved subscriptions')
  previous_fields = form_after_close.fields.dup
  release << true
  assert(work.instance_variable_get(:@thread).join(3), 'Preference read did not finish')
  snapshot = EltenGameRoom.table_watch_preferences_snapshot
  assert(snapshot == { state: :ready, games: ['makao'] } && calls == 1, 'Shared result did not reach cache')
  assert(form_after_close.fields == previous_fields, 'Late preference result touched a closed form')

  Form.background_settings_driver = lambda do |form|
    sections = form.fields.first
    sections.index = 3
    sections.trigger(:move)
    volume = form.fields.find { |field| field.header == 'Game sounds' }
    form.index = form.fields.index(volume)
    volume.index = 29
    form.instance_variable_get(:@timers).each(&:update)
    assert(form.fields[form.index].equal?(volume) && sections.index == 3 && volume.index == 29,
      'Loading subscriptions moved focus/category or overwrote local edits')
    watched = form.fields.find { |field| field.header.to_s.start_with?('Notify me about games') }
    assert(watched.is_a?(ListBox) && watched.game_indices == [1] && form.hidden_controls.include?(watched),
      'Ready subscriptions were missing, wrong or made another category visible')
    offset = GameRoomScreens::GameList::ACTION_ROWS
    watched.deselect_multiselection_indices([1 + offset])
    watched.select_multiselection_indices([offset])
    5.times { form.instance_variable_get(:@timers).each(&:update) }
    assert(watched.game_indices == [0], 'Refresh erased edited subscription selection')
    form.accept_button.trigger(:press)
  end
  ready = GameRoomScreens::Settings.new(values, games: games, table_watch_available: false,
    table_watch_loader: -> { EltenGameRoom.table_watch_preferences_snapshot })
  updated = ready.wait
  assert(ready.table_watch_baseline == ['makao'] && updated['table_watch_games'] == ['uno'], 'Loaded baseline/edit was lost')

  EltenGameRoom.table_watch_start(refresh: true)
  work = EltenGameRoom.instance_variable_get(:@table_watch_loader)
  Timeout.timeout(3) { arrived.pop }
  EltenGameRoom.table_watch_set_games(['uno'])
  release << true
  assert(work.instance_variable_get(:@thread).join(3), 'Old preference read did not finish')
  assert(EltenGameRoom.table_watch_preferences_snapshot[:games] == ['uno'], 'Late read overwrote confirmed settings')

  error = RuntimeError.new('simulated offline')
  EltenGameRoom.table_watch_start(refresh: true)
  work = EltenGameRoom.instance_variable_get(:@table_watch_loader)
  Timeout.timeout(3) { arrived.pop }
  release << true
  assert(work.instance_variable_get(:@thread).join(3), 'Failed read did not finish')
  assert(EltenGameRoom.table_watch_preferences_snapshot == { state: :unavailable, games: nil }, 'Error became an empty selection')
  50.times { EltenGameRoom.table_watch_start }
  assert(calls == 3 && receiver.games == ['uno'], 'Ticks retried failed preferences or erased the last confirmed cache')
ensure
  EltenGameRoom.table_watch_stop
  release << true
  work&.instance_variable_get(:@thread)&.join(3)
end
puts 'Settings: shared finite read, immediate local save, focus/edits preserved, late result and failure guards: OK'
