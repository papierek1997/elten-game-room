require_relative '../support/game_option_encoding'

repo = Struct.new(:players) do
  def players_for(_session); players; end
  def actor_of(event,_session); event['actor']; end
  def event_id(event); event['id']; end
end.new(%w[Alice Bob])
checks = {forms:0,checkbox_states:0,labels:0}
%w[en pl ru].each do |language|
  $option_host_language = language
  GameRoomTestLocalization.use_language(language)
  [GameRoomGames::Go.new,GameRoomGames::Roulette.new,GameRoomGames::DicePoker.new,GameRoomGames::Blackjack.new].each do |game|
    options = game.new_game_options('scoring'=>'chips','variant'=>game.id=='blackjack' ? 'social' : game.default_options['variant'])
    options.delete('variant') if options['variant'].nil?
    session = {'__id'=>81,'options'=>JSON.generate(options)}
    events = %w[blackjack dice_poker].include?(game.id) ? [{'id'=>1,'actor'=>'Alice','action'=>'ante','value'=>game.id=='dice_poker' ? '1' : ''}] : []
    replay = game.replay(session,events,repo)
    surface = GameSurfaces.build(game.surface_spec(replay,'Alice'))
    selected = nil
    surface.on_action { |action| selected = action }
    surface.fields.first.trigger(:select,[0])
    if selected
      status, = game.action_for(selected,replay,'Alice')
      raise "#{game.id} surface rejected" unless status==:ok
    end
    form = GameRoomUI::Form.new(surface.fields,program:EltenGameRoom.allocate,quiet:true)
    form.accept_button = Button.new('OK')
    GameOptionEncodingFixture.driver(checks).call(form)
    game.game_shortcuts(replay,'Alice')
    next unless game.id=='roulette'
    raise 'Roulette still declares the removed B form' if game.game_shortcuts(replay,'Alice').any? { |s| s.key=='b' }
    surface.fields.first.trigger(:select,[0])
    raise 'Roulette category did not expose a bet' unless selected && selected['action']=='bet'
    shortcut = game.surface_action_shortcut(selected,replay,'Alice')
    raise 'Roulette bet does not open its amount editor' unless shortcut&.kind==:number_input
    screen = GameScreen.allocate
    screen.instance_variable_set(:@program,EltenGameRoom.allocate)
    screen.instance_variable_set(:@game,game)
    # This binary-form/encoding fixture does not load the host dialog shell.
    # The complete native Enter/modal/speech path has its own regression in
    # roulette/stake_speech_native_test.rb; retain the real shared form here.
    screen.define_singleton_method(:dialog_open) {}
    screen.define_singleton_method(:dialog_close) {}
    Form.option_encoding_driver = lambda do |dialog|
      field = dialog.fields.first
      raise 'Roulette amount form lost its one selected numeric field/default' unless
        dialog.fields.size==1 && field.is_a?(EditBox) && field.flags==EditBox::Flags::Numbers && field.text=='10'
      field.set_text('17')
      GameOptionEncodingFixture.driver(checks).call(dialog)
    end
    input = screen.send(:number_shortcut_action,shortcut)
    raise 'Roulette selected bet/amount not accepted from form' unless input['amount']==17 && input['bet']==selected['bet'] && game.action_for(input,replay,'Alice').first==:ok
    Form.option_encoding_driver = ->(dialog) { dialog.cancel_button.trigger(:press) }
    raise 'Cancelled roulette amount form wrote a bet' unless screen.send(:number_shortcut_action,shortcut).nil?
  end
end
puts "New game binary forms: #{checks[:forms]} builds/focus checks, actual surface actions, custom roulette amount and cancellation passed in EN/PL/RU."
