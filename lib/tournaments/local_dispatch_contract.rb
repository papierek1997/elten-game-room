require_relative 'publication'
module GameRoomTournaments
  # Explicit local test availability, never inferred from registrations or
  # delayed analytics presence. All state shares the execution commit lock.
  module LocalDispatchContract
    Data = Publication::Data
    TTL = 60
    def self.root_fields(document)
      %w[version identity records readiness executions busy native] + (document.key?('dispatch') ? ['dispatch'] : [])
    end
    def self.validate!(document)
      return unless document.key?('dispatch')
      value = document['dispatch']
      unless value.is_a?(Hash) && (value.keys-['proposals']).sort == %w[availability policies] &&
          value.values.all? { |part| part.is_a?(Hash) } && value['policies'].size <= document['records'].size &&
          value['availability'].size <= document['records'].size
        raise Publication::Invalid, :sandbox_corrupt
      end
      value['policies'].each do |intent, policy|
        record = document['records'][intent]
        unless record && policy.is_a?(Hash) && (policy.keys-['consent_before_table']).sort == %w[max_tables plan_digest] &&
            (!policy.key?('consent_before_table') || [true,false].include?(policy['consent_before_table'])) &&
            policy['plan_digest'] == record['evidence']['plan_digest'] && Data.integer?(policy['max_tables'], 1) && policy['max_tables'] <= 32
          raise Publication::Invalid, :sandbox_corrupt
        end
        raise Publication::Invalid, :sandbox_corrupt if active(document, intent).size > policy['max_tables']
      end
      value['availability'].each do |intent, people|
        record = document['records'][intent]
        roster = record && record['evidence']['source']['roster'].map { |person| person['account'] }
        unless roster && value['policies'].key?(intent) && people.is_a?(Hash) && people.size <= 256
          raise Publication::Invalid, :sandbox_corrupt
        end
        people.each do |account, row|
          unless roster.include?(account) && row.is_a?(Hash) && row.keys.sort == %w[available expires_at observed_at revision] &&
              [true, false].include?(row['available']) && Data.integer?(row['revision'], 1) &&
              Data.integer?(row['observed_at']) && row['expires_at'] == row['observed_at'] + TTL
            raise Publication::Invalid, :sandbox_corrupt
          end
        end
      end
      claims = document['executions'].values.select { |row| !row['result'] && (policy(document, row['record_intent']) || row['operations'].key?('reserve')) }
      accounts = claims.flat_map { |row| row['request']['players'].map { |person| person['account'] } }
      raise Publication::Invalid, :sandbox_corrupt unless accounts.uniq.size == accounts.size
      LocalMatchProposals.validate!(document) if document.dig('dispatch','proposals')
    end
    def self.policy(document, intent); document.dig('dispatch', 'policies', intent); end
    def self.ready(document, intent, account, now)
      row = document.dig('dispatch', 'availability', intent, account)
      current = row && row['available'] && row['observed_at'] <= now && now < row['expires_at']
      {'state' => current ? 'ready' : 'withdrawn', 'revision' => "dispatch:#{row ? row['revision'] : 0}"}
    end
    def self.active(document, intent)
      document['executions'].values.select { |row| row['record_intent'] == intent && !row['result'] &&
        (policy(document, intent) || row['operations'].key?('reserve')) }
    end
    def self.reserve!(document, intent, request, now)
      configured = policy(document, intent)
      return unless configured
      same = ->(row) { row['request'].values_at('scope', 'match_id', 'leg', 'execution_generation') == request.values_at('scope', 'match_id', 'leg', 'execution_generation') }
      others = active(document, intent).reject(&same)
      raise CoordinationContract::Blocked, :table_limit if others.size >= configured['max_tables']
      accounts = request['players'].map { |person| person['account'] }
      competing = document['executions'].values.any? do |row|
        !same.call(row) && !row['result'] && (policy(document, row['record_intent']) || row['operations'].key?('reserve')) &&
          row['request']['players'].any? { |person| accounts.include?(person['account']) }
      end
      raise CoordinationContract::Blocked, :participants_busy if competing
      unless request['players'].all? { |person| ready(document, intent, person['account'], now)['state'] == 'ready' }
        raise CoordinationContract::Blocked, :participants_unavailable
      end
    end
  end
end
require_relative 'local_match_proposals'
