require_relative '../../support/cash_auction'

include GameRoomTest::Assertions

%w[en pl cs es ru].each do |language|
  GameRoomLocalization.boot(settings: {'interface_language'=>language}, host_language: language)
  content_language = {'pl'=>'pl-PL', 'ru'=>'ru-RU'}.fetch(language, 'en')
  f = CashAuctionFixture::Match.new(rules_version: 2, options: {'content_language_id'=>content_language})
  f.begin_round
  view = f.replay
  label = view.state[:category_label]
  packs = f.game.auction_content_packs(view.state[:options])
  bank = f.game.__send__(:question_bank, view.state[:options])
  source = packs.find { |pack| pack.id == bank.category_pack_id(view.state[:category]) }
  expected = "#{label} (#{source.title})"
  announcement = view.history.last.text
  assert(announcement.include?(expected), "#{language}: drawn category lost its actual source set titles: #{announcement}")
  assert_equal(1, announcement.scan(expected).length, 'Category and source were repeated')
  assert_equal(:auction, view.state[:phase])
  assert_equal(nil, view.state[:question], 'Displaying a set title drew/revealed the question early')
  assert_equal(2, view.accepted_events.length, 'A display-only change added a server event')
  assert_equal(view, GameRoomGames::CashAuction.new.replay(f.session, f.events, f.repository), 'Cold replay lost source display')
  assert(!announcement.include?(source.id), 'A category exposed internal pack IDs instead of titles')

  f.bid('Alice', 100)
  f.close_auction
  f.reveal_question
  chosen = packs.find { |pack| pack.id == f.replay.state[:question][:pack_id] }
  assert_equal(source, chosen, 'Question came from a different set than the category announcement')

  # A black chest is not a question category and must not pretend to have a
  # source set, even though a wheel category also exists in the native record.
  chest = CashAuctionFixture::Match.new(rules_version: 2, options: {'content_language_id'=>content_language})
  chest.begin_round(chest: true)
  chest_text = chest.replay.history.last.text
  chest.game.auction_content_packs(chest.replay.state[:options]).each do |pack|
    assert(!chest_text.include?(pack.title), 'Black-chest announcement acquired a misleading question set')
  end
end

puts 'PASS Cash Auction category source announcements: five languages, exact contributing sets, single announcement, no early question, no extra event, cold replay and black chests'
