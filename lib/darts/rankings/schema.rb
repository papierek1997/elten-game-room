module GameRoomDartsRankings
  DISPLAY_LIMIT = 30
  RECORDS_PER_PLAYER = 3

  module Schema
    TABLE = 'darts_ranked_results'.freeze
    PERSONAL_TABLE = 'darts_personal_records'.freeze
    RECORDS_BYTES = 4096
    COLUMNS = {'version'=>'integer', 'records_json'=>"string:#{RECORDS_BYTES}"}.freeze
    PERSONAL_COLUMNS = COLUMNS
    TABLES = {
      TABLE=>{
        'visibility'=>'public', 'unique_per_user'=>false, 'columns'=>COLUMNS,
        'permissions'=>%w[select insert delete],
        'limits'=>{'max_select_limit'=>1000}
      },
      PERSONAL_TABLE=>{
        'visibility'=>'shared', 'unique_per_user'=>false, 'columns'=>PERSONAL_COLUMNS,
        'permissions'=>%w[select insert delete], 'limits'=>{'max_select_limit'=>1000}
      }
    }.freeze
  end
end
