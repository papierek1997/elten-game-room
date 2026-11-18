require_relative '../support/widget_presets'

# Exercise the production widget's foreground callback and native Tasks worker,
# without opening a desktop window or probing auxiliary tables.
def loop_update(*); Thread.pass; end

tables = Struct.new(:access_state) do
  def available?; access_state == :available; end
  def stamp_required?; access_state == :stamp_required; end
end.new(:unchecked)
app = EltenGameRoom.allocate
app.define_singleton_method(:initialize_services) {}
app.define_singleton_method(:widget_active?) { true }
app.define_singleton_method(:game_room_settings) { {'table_presets' => []} }
app.instance_variable_set(:@server_tables, tables)
notices, reads = [], 0
app.define_singleton_method(:alert) { |message| notices << message }
widget = app.send(:build_widget_control)
widget.instance_variable_set(:@loader, -> { reads += 1; [WidgetSnapshot.new(table: {'__id' => 7})] })
widget.instance_variable_set(:@labeler, ->(_) { 'Bob, UNO' })
widget.instance_variable_set(:@id_for, ->(row) { row.table.fetch('__id') })
begin
  %i[unchecked stamp_required unavailable available].each do |state|
    tables.access_state = state
    3.times { widget.focus }
    assert(widget.options == ['Bob, UNO'], "#{state}: table discovery failed without auxiliary access")
    assert(notices.empty?, "#{state}: passive widget entry announced auxiliary access: #{notices.inspect}")
  end
  assert(reads == 12, 'Widget re-entry did not load its current table list')
  tables.access_state = :unchecked
  3.times { app.send(:run_network_task, 'Ordinary LiveSessions work', silent: true) { true } }
  assert(notices.empty?, 'An unchecked provider was reported as a failed table probe')
  tables.access_state = :stamp_required
  3.times { app.send(:announce_server_table_access) }
  assert(notices.size == 1 && notices.first.include?('most likely using developer mode'),
    'A confirmed access refusal was hidden or repeated')
ensure
  widget.close
end
puts 'PASS widget availability: fresh discovery without false/repeated table warnings, pending probe remains unknown, confirmed entry denial still announced once'
