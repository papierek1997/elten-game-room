require_relative 'knockout_round'
require_relative 'knockout_series'

module GameRoomTournaments
  module KnockoutWinSeries
    module_function
    def progress(base:, history:, target:)
      raise Publication::Invalid, :invalid_knockout_configuration unless base.is_a?(Hash)
      expected=KnockoutRound.from_metadata(base)
      raise Publication::Invalid,:invalid_knockout_configuration unless base==expected && base['players_per_match']==2
      raise Publication::Invalid,:invalid_phase_results unless history.is_a?(Array) && history.size<=4096
      history=Standings.validated_results(units:base['seeds'],results:history,max_results:4096)
      pairs=base['matches'].to_h{|match|[match['participants'].sort,match]}
      raise Publication::Invalid,:invalid_phase_results unless history.all?{|row|pairs.key?(row['participants'].sort)}
      series=base['matches'].map do |match|
        KnockoutSeries.wins_projection(units:match['participants'],results:history.select{|row|row['participants'].sort==match['participants'].sort},id:match['id'],target:target)
      end
      summaries=series.filter_map{|row|row['summary']}
      sports=KnockoutRound.progress(seeds:base['seeds'],players_per_match:2,round_number:base['round'],results:summaries,bracket_groups:base['bracket_groups'])
      Publication::Data.freeze_tree(Publication::Data.copy({'series'=>series,'sports'=>sports,'summaries'=>summaries},max_bytes:1_048_576,max_nodes:65_536,max_depth:16))
    end
    def build(base:,history:,target:,attempt:)
      raise Publication::Invalid,:invalid_knockout_configuration unless attempt.is_a?(Integer) && attempt.between?(1,4096)
      view=progress(base:base,history:history,target:target)
      pending=base['matches'].zip(view['series']).reject{|_match,series|series['state']=='completed'}.map(&:first)
      raise Publication::Invalid,:tournament_completed if pending.empty?
      metadata={'base_plan'=>base,'history'=>history,'target'=>target,'attempt'=>attempt}
      generation=Digest::SHA256.hexdigest(JSON.generate(['knockout-win-series-v1',metadata]))
      matches=pending.map.with_index{|match,i|{'id'=>"#{generation}:#{i+1}",'participants'=>match['participants']}}
      Publication::Data.freeze_tree(Publication::Data.copy(base.merge('generation'=>generation,'matches'=>matches,'series'=>metadata),max_bytes:1_048_576,max_nodes:65_536,max_depth:16))
    end
    def from_metadata(metadata)
      series=metadata['series']
      CoordinationRequest.fields!(series,%w[base_plan history target attempt])
      plan=build(base:series['base_plan'],history:series['history'],target:series['target'],attempt:series['attempt'])
      raise Publication::Invalid,:phase_changed unless plan.slice('round','seeds','players_per_match','generation','bracket_groups')==metadata.slice('round','seeds','players_per_match','generation','bracket_groups')
      plan
    end
  end
end
