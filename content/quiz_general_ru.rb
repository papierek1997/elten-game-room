# encoding: UTF-8
# Generated metadata for the editorial Russian question pack.
require_relative "../lib/game_content"
GameRoomContent.registry.register_pack(GameRoomContent::Pack.new(
  id: "quiz.general.ru",
  set_id: "quiz.general.ru",
  kind: :quiz,
  language_id: "ru-RU",
  version: 1,
  title: "Общие знания",
  game_ids: ["quiz"],
  license: "CC0-1.0",
  author: "ELTEN Game Room editorial",
  entry_count: 36,
  checksum: "6a9a27e8bad222b3dbe3869d22eef78f8d901098ff58a6d6d1a7364aaaf92555",
  loader: lambda {
    require_relative "quiz_general_ru_data"
    GameRoomContent::Pack6c196d7dcfe391c7729e9d7f.load
  }
))
