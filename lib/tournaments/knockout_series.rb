require_relative 'standings'
module GameRoomTournaments
  module KnockoutSeries
    module_function
    # An organizer's no-award decision closes a knockout pairing, not a draw
    # that can be replayed. Keep unplayed return legs as derived status only;
    # never fabricate another result receipt or small-point contribution.
    def voided_matches(candidate:, receipts:)
      return [] unless candidate['format']=='knockout' && candidate.dig('knockout','rematch') &&
        !candidate.dig('knockout','qualification')
      matches=candidate.fetch('matches')
      recorded=receipts.map { |row|[row['match_id'],row['leg']] }
      closed=receipts.filter_map do |row|
        match=matches.find { |item|[item['match_id'],item['leg']]==[row['match_id'],row['leg']] }
        match if match && row.dig('summary','resolution')=='all_zero'
      end
      matches.filter_map do |match|
        next if recorded.include?([match['match_id'],match['leg']])
        source=closed.find { |item|(item['unit_ids'] || item['players']).sort==(match['unit_ids'] || match['players']).sort }
        match.slice('match_id','leg').merge('source'=>source.slice('match_id','leg')) if source
      end
    end
    # Ordered game receipts, not a best-of-N limit: draws never consume a win.
    # The next game may be planned only while this projection is awaiting_games.
    def wins_projection(units:, results:, id:, target:)
      unless target.is_a?(Integer) && target.between?(1,99) && units.is_a?(Array) && units.size==2
        raise Publication::Invalid,:invalid_win_target
      end
      # One pairing can span many phases when draws do not consume wins.
      # Reuse the full-history validator, not the ordinary256-result aggregate.
      # Its identity, shape and byte/node budgets still apply to every row.
      results=Standings.validated_results(units:units,results:results,max_results:4096)
      wins=units.to_h{|unit|[unit,0]}
      champion=nil
      no_winner=false
      results.each do |result|
        raise Publication::Invalid,:result_after_series_finished if champion || no_winner
        raise Publication::Invalid,:invalid_series_result unless result['participants'].sort==units.sort && result['winners'].size<=1
        winner=result['winners'].first
        no_winner = result['resolution']=='all_zero'
        if winner
          wins[winner]+=1
          champion=winner if wins[winner]==target
        end
      end
      scores=nil
      if !results.empty? && results.all?{|result|result['scores']}
        orders=results.map{|result|result.fetch('score_order','higher')}.uniq
        raise Publication::Invalid,:inconsistent_score_order unless orders.size==1
        scores=units.to_h{|unit|[unit,results.sum{|result|result['scores'].fetch(unit)}]}
      end
      summary=champion && {'id'=>id,'participants'=>units,'winners'=>[champion],'scores'=>scores}
      summary={'id'=>id,'participants'=>units,'winners'=>[],'scores'=>nil,'resolution'=>'all_zero'} if no_winner
      summary['score_order']=results.first.fetch('score_order','higher') if summary && scores
      Publication::Data.freeze_tree(Publication::Data.copy({'state'=>champion || no_winner ? 'completed' : 'awaiting_games',
        'target'=>target,'wins'=>wins,'played'=>results.size,'next_game'=>champion || no_winner ? nil : results.size+1,'summary'=>summary}))
    end
    # Both legs must have committed receipts. Match points decide first;
    # complete game scores break a split result, otherwise play another game.
    def aggregate(units:, results:, id:)
      if results.any? { |result| result['resolution']=='all_zero' }
        Standings.calculate(units:units,results:results)
        return {'id'=>id,'participants'=>units,'winners'=>[],'scores'=>nil,'resolution'=>'all_zero'}
      end
      return nil unless results.size == 2
      table = Standings.calculate(units: units, results: results, points: Standings::MATCH_POINTS)
      top = table.select { |row| row['points'] == table.map { |row| row['points'] }.max }
      scores = nil
      if table.all? { |row| row['scored_matches'] == 2 }
        scores = table.to_h { |row| [row['unit'], row['score_for']] }
        if top.size > 1
          order = results.find { |row| row['scores'] }.fetch('score_order', 'higher')
          best = order == 'lower' ? scores.values.min : scores.values.max
          top = top.select { |row| scores[row['unit']] == best }
        end
      end
      summary = {'id' => id, 'participants' => units, 'winners' => top.size == 1 ? [top.first['unit']] : [], 'scores' => scores}
      summary['score_order'] = results.first['score_order'] if results.first.key?('score_order')
      summary
    end
  end
end
