require_relative '../support/background_help_game_screen'

h, screen = screen_fixture(GameRoomGames::FourInARow.new)
sender = TableActivityRepository.new(server_tables: Object.new, transport: h.transports.fetch('Alice'))
recipient = TableActivityRepository.new(server_tables: Object.new, transport: h.transports.fetch('Bob'))
sent = []
screen.instance_variable_set(:@send_chat, lambda do |table, text, _members|
  sent << text
  sender.append(table: table, kind: 'chat', message: text)
end)
message = ('Zażółć gęślą jaźń. ' * 120)[0, 2000].rstrip
stage = :send
Form.driver = lambda do |_form|
  layout = screen.instance_variable_get(:@layout)
  case stage
  when :send
    stage = :receive
    layout.form.index = layout.form.fields.index(layout.chat)
    layout.chat.set_text(message)
    layout.chat.trigger(:select)
  when :receive
    assert(sent == [message], 'GameScreen duplicated or shortened the sent message')
    assert(recipient.entries_for(h.table).map(&:message) == [message], 'Recipient did not receive the full GameScreen message')
    assert(layout.chat.text.empty? && layout.focus_location == [:chat, 0], 'Sending failed to clear the submitted draft or moved focus')
    assert(h.events('Alice').empty?, 'Sending chat also performed a game move')
    layout.back_button.trigger(:press)
  end
end
h.as('Alice') { assert(screen.run == :back, 'Leaving the game changed') }
assert(stage == :receive, 'The real GameScreen loop did not reach chat')
puts 'PASS long chat through GameScreen and both repositories: one send, full delivery, unchanged game/focus, cleared draft'
