module GameRoomGames
  module KrowaServerSchema
    TABLES = {
      "krowa_daily_completions" => {
        "visibility" => "shared", "columns" => {"day_key" => "integer", "status" => "integer"},
        "permissions" => ["select", "insert"], "indexes" => [["day_key"]],
        "limits" => {"max_select_limit" => 500}
      },
      "krowa_daily_scores" => {
        "visibility" => "public", "columns" => {"day_key" => "integer", "attempts" => "integer"},
        "permissions" => ["select", "insert"], "indexes" => [["day_key", "attempts"]],
        "limits" => {"max_select_limit" => 500}
      },
      "krowa_word_scores" => {
        "visibility" => "public", "columns" => {"word" => "string:32", "attempts" => "integer"},
        "permissions" => ["select", "insert"], "indexes" => [["word", "attempts"]],
        "limits" => {"max_select_limit" => 2000}
      },
      "krowa_tower_scores" => {
        "visibility" => "public",
        "columns" => {"run_code" => "string:64", "rounds" => "integer", "participants" => "string:1024"},
        "permissions" => ["select", "insert"], "indexes" => [["run_code"], ["rounds"]],
        "limits" => {"max_select_limit" => 500}
      },
      "krowa_tower_rounds" => {
        "visibility" => "public",
        "columns" => {"run_code" => "string:64", "round" => "integer", "word" => "string:32", "attempts" => "integer", "solved" => "integer"},
        "permissions" => ["select", "insert"], "indexes" => [["run_code", "round"]],
        "limits" => {"max_select_limit" => 500}
      }
    }.freeze
  end
end
