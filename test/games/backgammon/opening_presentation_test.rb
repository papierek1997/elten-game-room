require_relative '../../support/background_help_game_screen'
require_relative '../../../games/backgammon'

[[[4, 3]], [[3, 6]], [[2, 2], [3, 6]]].each do |draws|
  game = GameRoomGames::Backgammon.new
  harness, screen = screen_fixture(game)
  begin
    heard = []
    screen.define_singleton_method(:speak_table_automatically) { |message| heard << message.to_s }
    screen.send(:process_new_events, harness.replay('Alice'))
    heard.clear
    context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(87))
    draws.each do |dice|
      harness.view('Alice').next_random_values = dice
      harness.submit('Alice', {'kind'=>'dice', 'action'=>'opening'}, context: context)
      screen.send(:process_new_events, harness.replay('Alice'))
    end
    starter = draws.last.first > draws.last.last ? 'Alice' : 'Bob'
    text = heard.join("\n")
    assert(text.include?("Alice rolls #{draws.last.first}."), 'Opening lost the first die')
    assert(text.include?("Bob rolls #{draws.last.last}."), 'Opening lost the second die')
    assert(text.scan("#{starter} starts.").size == 1, 'Opening announces its starter more than once')
    assert(!text.include?("It is #{starter}'s turn.") && !text.include?('It is your turn.'), 'Shared turn announcement repeats the opening starter')
    history = screen.send(:combined_history_items, harness.replay('Alice')).join("\n")
    assert(history.scan("#{starter} starts.").size == 1 && !history.include?("It is #{starter}'s turn."), 'The history repeats the opening starter')
    count = heard.size
    screen.send(:process_new_events, harness.replay('Alice'))
    assert(heard.size == count, 'Quiet refresh repeats the opening')
  ensure
    screen.send(:stop_session_runner)
  end
end
puts 'PASS native server opening: both starters and a tie retain both dice, one starter announcement, no duplicate history or refresh speech'
