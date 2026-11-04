require_relative 'publication'

module GameRoomTournaments
  # Informational projection only. Never changes points, qualification,
  # receipts or bracket order. Teams remain single sporting units.
  module TournamentFinishSummary
    module_function

    def build(candidate:,results:,history:,usernames:)
      phases=history.map { |entry| [entry.fetch('candidate'),entry.fetch('view').fetch('standings')] }
      phases << [candidate,results.fetch('standings')]
      units={}
      phases.each do |phase,standings|
        if phase['membership']
          phase.fetch('membership').fetch('units').each { |unit| units[unit.fetch('unit_id')]=unit.fetch('accounts') }
        else
          standings.each { |row| units[row.fetch('unit')]=[row.fetch('unit')] }
        end
      end

      standings=results.fetch('standings')
      knockout=candidate['format']=='knockout' && !candidate.dig('knockout','qualification')
      winners=knockout ? Array(results['champion']) : standings.select { |row| row.fetch('place')==1 }.map { |row| row.fetch('unit') }
      places={}
      if knockout
        unless winners.empty?
          winners.each { |unit| places[unit]=1 }
          standings.each { |row| places[row.fetch('unit')] ||= winners.size+1 }
          phases.reverse_each do |phase,table|
            # Qualification tie-breaks do not establish an ordering between
            # eliminated players from different groups.
            next if phase.dig('knockout','qualification')
            eliminated=table.map { |row| row.fetch('unit') }.reject { |unit| places.key?(unit) }
            place=places.size+1
            eliminated.each { |unit| places[unit]=place }
          end
        end
      else
        standings.each { |row| places[row.fetch('unit')]=row.fetch('place') }
      end

      names=usernames.to_h
      value={
        'winners'=>winners.map { |unit| units.fetch(unit).map { |account| names.fetch(account,account) }.join(' + ') },
        'places'=>places.each_with_object({}) { |(unit,place),all| units.fetch(unit).each { |account| all[account]=place } },
        'team_mode'=>candidate.key?('membership')
      }
      Publication::Data.freeze_tree(Publication::Data.copy(value,max_bytes:131_072,max_nodes:2048,max_depth:5))
    end
  end
end
