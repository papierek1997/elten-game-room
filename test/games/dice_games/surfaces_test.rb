require_relative "../../support/game_option_encoding"

repo = Struct.new(:players) do
  def players_for(_session); players; end
  def actor_of(event, _session); event.fetch('actor'); end
  def event_id(event); event.fetch('id'); end
end.new(%w[Alice Bob Carol])

checks = {forms: 0, checkbox_states: 0, labels: 0}
%w[en pl ru].each do |language|
  $option_host_language = language
  GameRoomTestLocalization.use_language(language)
  poker = GameRoomGames::DicePoker.new
  session = {'__id'=>71, 'options'=>JSON.generate(poker.normalize_options({}))}
  replay = poker.replay(session, [], repo)
  poker.game_shortcuts(replay,'Alice')
  context = GameRoomGames::ActionContext.new(session_id:71, random_source:GameRoomRandom::SeededSource.new(57))
  surface = GameSurfaces.build(poker.surface_spec(replay, 'Alice'))
  action = nil
  surface.on_action { |input| action = input }
  surface.fields.first.trigger(:select, [0])
  status, plan = poker.action_for(action, replay, 'Alice', context:context)
  raise 'Initial poker Enter is not a real roll' unless status == :ok
  event = {'id'=>1,'actor'=>'Alice','action'=>plan.events.first.action,'value'=>plan.events.first.value}
  played = poker.replay(session,[event],repo)
  shortcuts = poker.game_shortcuts(played,'Alice')
  raise 'Shared turn key was replaced' unless shortcuts.any? { |shortcut| shortcut.key == 't' && shortcut.kind == :announcement }
  raise 'Keep hand key missing' unless shortcuts.any? { |shortcut| shortcut.key == 'k' && shortcut.kind == :action }
  surface = GameSurfaces.build(poker.surface_spec(played,'Alice'),state:surface.state)
  surface.on_action { |input| action = input }
  surface.fields.first.trigger(:select, [0])
  surface.fields.first.trigger(:select, [0])
  raise 'Keep hand action bypasses the model' unless poker.action_for(action,played,'Alice',context:context).first == :ok
  form = GameRoomUI::Form.new(surface.fields,program:EltenGameRoom.allocate,quiet:true)
  form.accept_button = Button.new('OK')
  GameOptionEncodingFixture.driver(checks).call(form)

  %w[rdr classic perudo].each do |variant|
    game = GameRoomGames::LiarsDice.new
    session = {'__id'=>72,'options'=>JSON.generate(game.normalize_options('variant'=>variant))}
    contexts = repo.players.to_h do |player|
      vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
      [player,GameRoomGames::ActionContext.new(session_id:72,hidden_submissions:vault,random_source:GameRoomRandom::SeededSource.new(player.bytes.sum))]
    end
    events = []
    repo.players.each do |player|
      current = game.replay(session,events,repo)
      status, plan = game.action_for({'action'=>'commit'},current,player,context:contexts[player])
      raise 'Commit rejected' unless status == :ok
      events << {'id'=>events.size+1,'actor'=>player,'action'=>plan.events.first.action,'value'=>plan.events.first.value}
    end
    status, plan = game.action_for({'action'=>'deal'},game.replay(session,events,repo),'Alice',context:contexts['Alice'])
    raise 'Deal rejected' unless status == :ok
    events << {'id'=>4,'actor'=>'Alice','action'=>plan.events.first.action,'value'=>plan.events.first.value}
    current = game.replay(session,events,repo)
    game.prepare_view(current,'Alice',context:contexts['Alice'])
    spec = game.surface_spec(current,'Alice')
    raise 'Ticket became a card hand' if game.playable_card_navigation(current,'Alice')
    raise 'Screen expands every bid' unless spec.items.size <= 9
    surface = GameSurfaces.build(spec)
    selected = nil
    surface.on_action { |input| selected = input }
    surface.fields.first.index = 1
    surface.fields.first.trigger(:select,[1])
    raise 'List bid is not legal' unless game.action_for(selected,current,'Alice',context:contexts['Alice']).first == :ok
    screen = GameScreen.allocate
    screen.instance_variable_set(:@program,EltenGameRoom.allocate)
    screen.instance_variable_set(:@game,game)
    shortcut = game.game_shortcuts(current,'Alice').find { |s| s.key == 'b' }
    raise 'Custom bid form is missing' unless shortcut
    Form.option_encoding_driver = lambda do |dialog|
      dialog.fields.first.set_text('3')
      GameOptionEncodingFixture.driver(checks).call(dialog)
    end
    input = screen.send(:form_shortcut_action,shortcut)
    raise 'Native numeric input lost its text value' unless input['quantity'] == '3'
    raise 'Custom bid form value rejected' unless game.action_for(input,current,'Alice',context:contexts['Alice']).first == :ok
    Form.option_encoding_driver = ->(dialog) { dialog.cancel_button.trigger(:press) }
    raise 'Cancelling the bid form writes a move' unless screen.send(:form_shortcut_action,shortcut).nil?
    Form.option_encoding_driver = GameOptionEncodingFixture.driver(checks)
    spec.items.each { |item| item.label + ' — выбранное поле' }
    form = GameRoomUI::Form.new(surface.fields,program:EltenGameRoom.allocate,quiet:true)
    form.accept_button = Button.new('OK')
    GameOptionEncodingFixture.driver(checks).call(form)
    game.prepare_view(current,'Observer',context:contexts['Alice'])
    raise 'Spectator sees own dice controls' unless game.surface_spec(current,'Observer').items.one?
    raise 'Spectator can bid' unless game.legal_actions(current,'Observer').empty?
    raise 'Viewer switch retained a private cup' unless game.instance_variable_get(:@private_view).nil?
  end
end
puts "Dice game binary UI: #{checks[:forms]} forms, native custom bids, cancellation, dice actions, viewer isolation and EN/PL/RU announcements passed"
