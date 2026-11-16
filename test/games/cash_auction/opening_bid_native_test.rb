require_relative '../../support/cash_auction_native'

include GameRoomTest::Assertions
rules = GameRoomCashAuction::Rules
game = GameRoomGames::CashAuction.new
context = GameRoomGames::ActionContext.new(now:101)

%w[en pl-PL cs-CZ es-ES ru-RU].each do |language|
  GameRoomLocalization.boot(settings:{'interface_language'=>language, 'known_languages'=>[language]})
  options = game.table_creation_options('content_language_id'=>'en', 'ante'=>300)
  fixture = CashAuctionNative::Fixture.new(options:options)
  begin
    input = fixture.input
    fixture.type('299')
    fixture.press(13)
    refused = fixture.actions.last
    status, plan = fixture.game.action_for(refused, fixture.replay, 'Alice', context:context)
    assert_equal([:invalid_bet, nil], [status, plan])
    error = fixture.game.move_error_for(status, replay:fixture.replay, actor:'Alice')
    assert(error.include?('300') && error.include?('9700'), 'Opening refusal omitted the inclusive limits')
    assert(!error.include?('%{'), 'Opening refusal contains unexpanded placeholders')
    assert(language == 'en' || !error.start_with?('Enter an amount'), 'Opening refusal is untranslated')
    assert_equal(false, fixture.surface.action_rejected(refused, status))
    assert_equal('299', input.text, 'A refused first bid erased the draft')
    assert_equal([:game, 0], fixture.layout.focus_location)
    fixture.type('300')
    fixture.press(13)
    accepted = fixture.actions.last
    assert_equal(:ok, fixture.game.action_for(accepted, fixture.replay, 'Alice', context:context).first)
    assert(rules.bid!(fixture.state, 0, 300, now:101, revision:1), 'Reducer refused the minimum opening')
    assert(fixture.surface.action_accepted(accepted), 'Accepted opening did not acknowledge the editor')
    fixture.refresh
    assert(input.equal?(fixture.input), 'Opening replaced the native input control')
    assert_equal('', input.text)
    assert_equal([:game, 0], fixture.layout.focus_location)
    fixture.type('301')
    fixture.press(13)
    assert_equal(:ok, fixture.game.action_for(fixture.actions.last, fixture.replay, 'Alice', context:context).first,
      'The native editor imposed an unrequested raise increment')
  ensure
    fixture.close
  end

  short = CashAuctionNative::Fixture.new(options:options.merge('starting_points'=>599))
  begin
    short.type('A')
    short.press(13)
    status, plan = short.game.action_for(short.actions.last, short.replay, 'Alice', context:context)
    assert_equal([:invalid_bet, nil], [status, plan])
    error = short.game.move_error_for(status, replay:short.replay, actor:'Alice')
    assert(error.include?('300'), 'A short balance refusal omitted the opening minimum')
    assert(!error.include?(' A '), 'A short balance refusal recommends an unavailable all-in')
    assert(language == 'en' || !error.start_with?('You do not have enough'), 'Short-balance refusal is untranslated')
    assert_equal('A', short.input.text)
  ensure
    short.close
  end
end

puts 'PASS Cash Auction native opening bids: five interface languages, inclusive minimum, short all-in refusal, retained drafts/focus/control, accepted ACK and unchanged one-point raises (capture-only, no live server)'
