require_relative "../support/game_option_form"

# Validation re-enters Form#wait on the same focused checkbox. This fixture
# normally exits in one pass; expose its focus method for the second pass.
class CheckBox
  def focus; speak(header); end
end

games = [GameRoomGames::AxelPong.new, GameRoomGames::AudioBall.new]
games.each do |game|
  defaults = game.default_options
  assert(defaults['p2p_enabled'] == false && defaults['p2p_participants_limit'] == 8, "#{game.id}: wrong defaults")
  definitions = game.effective_option_definitions
  keys = definitions.map(&:key)
  assert(keys.uniq == keys, 'duplicate option keys')
  assert(keys.index('p2p_participants_limit') == keys.index('p2p_enabled') + 1, 'limit is not next to checkbox')
  limit_definition = definitions.find { |d| d.key == 'p2p_participants_limit' }
  assert(!game.option_visible?(limit_definition, defaults), 'disabled limit is visible')
  [0, 1, 8, 32, 0x7fffffff].each do |limit|
    values = game.normalize_options(p2p_enabled: true, p2p_participants_limit: limit.to_s)
    assert(game.validation_error(values).nil?, "#{game.id}: rejected native limit #{limit}")
    assert(game.option_visible?(limit_definition, values), 'enabled limit hidden')
    assert(game.options_from_json(JSON.generate(values)) == values, 'table/preset serialization lost P2P')
    assert(GameRoomRealtime::P2POptions.session_options(values) == {p2p: :full, p2p_participants_limit: limit}, 'not full P2P')
  end
  ['', '8x', '1.5', -1, nil, false, 0x80000000].each do |bad|
    values = {'p2p_enabled' => true, 'p2p_participants_limit' => bad}
    assert(game.validation_error(values), "#{game.id}: invalid limit #{bad.inspect} accepted")
    assert(game.validation_error(game.normalize_options(values)), 'normalization hid invalid input')
    values['p2p_enabled'] = false
    assert(game.validation_error(values).nil?, 'inactive field blocks relay table')
    assert(GameRoomRealtime::P2POptions.session_options(values).empty?, 'inactive field affects native request')
  end

  errors, remembered = [], []
  editor = GameRoomOptionEditor.new(program: EltenGameRoom.allocate,
    defaults: ->(_game, rows) { rows.to_h { |d| [d.key, d.default] } },
    remember: ->(*values) { remembered << values }, alert: ->(message) { errors << message })
  step = 0
  first_form = nil
  Form.driver = lambda do |form|
    first_form ||= form
    assert(form.equal?(first_form), 'P2P toggle rebuilt the form')
    checkbox = form.fields.find { |field| field.header == definitions.find { |d| d.key == 'p2p_enabled' }.label }
    limit = form.fields.find { |field| field.header == limit_definition.label }
    if step == 0
      assert(!checkbox.checked && limit.text == '8' && form.hidden_controls.include?(limit), 'wrong initial controls')
      form.index = form.fields.index(checkbox)
      checkbox.checked = true
      checkbox.trigger(:change)
      assert(form.fields[form.index].equal?(checkbox) && !form.hidden_controls.include?(limit), 'toggle steals focus or hides limit')
      limit.set_text('12')
      checkbox.checked = false
      checkbox.trigger(:change)
      assert(form.hidden_controls.include?(limit), 'toggle off leaves limit visible')
      checkbox.checked = true
      checkbox.trigger(:change)
      assert(limit.text == '12', 'toggle reset custom limit')
      limit.set_text('')
    else
      assert(step == 1 && errors.length == 1 && limit.text.empty?, 'invalid edit was not retained')
      limit.set_text('12')
    end
    step += 1
    form.accept_button.trigger(:press)
  end
  result = editor.edit(game, creating_table: true)
  assert(step == 2 && remembered.length == 1, 'validation failed to allow corrected input')
  assert(result[:game_options].values_at('p2p_enabled', 'p2p_participants_limit') == [true, 12], 'saved wrong P2P settings')
  assert(result[:private_table] == false, 'P2P changed table privacy')
end

EltenGameRoom::GAME_REGISTRY.ids.each do |id|
  next if %w[axel_pong audio_ball].include?(id)
  game = EltenGameRoom::GAME_REGISTRY.build(id)
  assert(game.effective_option_definitions.none? { |d| d.key.start_with?('p2p_') }, "P2P leaked to #{id}")
end
puts 'PASS P2P options: two games, defaults, validation, native range, adjacent dependent field, focus and serialization'
