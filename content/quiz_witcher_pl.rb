require_relative "../lib/game_content"

witcher_sets = [
  {
    id: "quiz.witcher.pl",
    set_id: "quiz.witcher",
    title: "Wiedźmin",
    scope: :all,
    entry_count: 384,
    checksum: "a9ff6f5134a19b85a1c82e4a881bef8915a547d0fdbbc5defc5d9de29ecc2e0d"
  },
  {
    id: "quiz.witcher.g.pl",
    set_id: "quiz.witcher.g",
    title: "Wiedźmin — gry",
    scope: :games,
    entry_count: 144,
    checksum: "0708e41e556fe241a34f513098fc87de08568116ddf329d670f21aab5baf72c1"
  },
  {
    id: "quiz.witcher.b.pl",
    set_id: "quiz.witcher.b",
    title: "Wiedźmin — książki i ekranizacje",
    scope: :books_screen,
    entry_count: 240,
    checksum: "dbd822f4712731e95df240e1db45fefcd54e62b32ae14cccf74f6aefcfc8bf13"
  }
].freeze

witcher_sets.each do |definition|
  scope = definition.fetch(:scope)
  GameRoomContent.registry.register_pack(GameRoomContent::Pack.new(
    id: definition.fetch(:id),
    set_id: definition.fetch(:set_id),
    kind: :quiz,
    language_id: "pl-PL",
    version: 3,
    title: definition.fetch(:title),
    game_ids: ["quiz"],
    license: "CC BY-SA 3.0 (Fandom, Wiedźmin Wiki)",
    author: "ELTEN Game Room",
    entry_count: definition.fetch(:entry_count),
    checksum: definition.fetch(:checksum),
    loader: lambda {
      require_relative "quiz_witcher_pl_sets"
      GameRoomContent::WitcherPolishSets.load(scope)
    }
  ))
end
