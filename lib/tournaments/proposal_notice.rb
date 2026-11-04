# encoding: UTF-8
require_relative 'publication'
require_relative 'server_plan_document'

module GameRoomTournaments
  # Notifications contain references, never readiness or authority. An injected
  # trusted backend must read and conditionally answer the current proposal.
  class ProposalNotice
    TYPE = 'game_room.tournament_proposal'.freeze
    ACTION = :open_tournament_proposal
    RESPONSES = %i[confirmed awaiting_consent declined pending conflict unknown].freeze
    FIELDS = %w[version backend_identity publication_ref schedule_id match_id leg token recipient].freeze
    Data = Publication::Data
    class Unavailable < StandardError; end
    class Stale < StandardError; end

    def self.metadata(value)
      value = Data.copy(value, max_bytes: 2048, max_depth: 4, max_nodes: 64)
      unless value.is_a?(Hash) && ((value['version']==1 && value.keys.sort==FIELDS.sort) ||
          (value['version']==2 && value.keys.sort==(FIELDS+['stage']).sort && %w[consent enter].include?(value['stage'])))
        raise Publication::Invalid, :invalid_proposal_notice
      end
      Data.text!(value['backend_identity'], bytes: 256)
      %w[schedule_id match_id token].each { |key| ServerPlanDocument.digest!(value[key]) }
      reference = value['publication_ref']
      raise Publication::Invalid, :invalid_proposal_notice unless reference.is_a?(Hash) && reference.keys.sort == %w[author publication_key]
      Data.account(reference['author'])
      Data.key!(reference['publication_key'])
      raise Publication::Invalid, :invalid_proposal_notice unless [1, 2].include?(value['leg'])
      value['recipient'] = Data.account(value['recipient']).downcase
      Data.freeze_tree(value)
    end

    def initialize(backend:, context:, clock:)
      @backend, @context, @clock = backend, context, clock
      @scope = scope
      @changed = false
    end

    # Worker only. Sender is supplied by the authenticated host notification,
    # not by metadata. Rechecking on open prevents cache-based consent.
    def inspect(metadata:, sender:, delivery: false)
      notice = self.class.metadata(metadata)
      current!
      raise Unavailable, 'Shared proposals are not connected' unless @backend && @backend.respond_to?(:lookup_proposal)
      sender = Data.account(sender).downcase
      own_boundary = delivery ? sender == @scope['account'] : notice['recipient'] == @scope['account']
      raise Stale, 'Different recipient or backend' unless own_boundary && notice['backend_identity'] == @scope['backend_identity']
      proof = Data.copy(@backend.lookup_proposal(notice: notice), max_bytes: 8192, max_depth: 8, max_nodes: 256)
      current!
      unless proof.is_a?(Hash) && proof.keys.sort == %w[accepted metadata players revision sender status window] &&
          proof['status'] == 'confirmed' && self.class.metadata(proof['metadata']) == notice && proof['sender'] == sender &&
          proof['players'].is_a?(Array) && proof['players'].size.between?(2, 8) && proof['players'].uniq == proof['players'] &&
          proof['players'].all? { |account| Data.account(account).downcase == account } && proof['players'].include?(notice['recipient']) &&
          proof['accepted'].is_a?(Array) && proof['accepted'].uniq == proof['accepted'] && (proof['accepted'] - proof['players']).empty? &&
          proof['window'].is_a?(Hash) && proof['window'].keys.sort == %w[closes opens] &&
          Data.integer?(proof['window']['opens']) && Data.integer?(proof['window']['closes']) &&
          proof['window']['opens'] <= @clock.call && @clock.call < proof['window']['closes']
        raise Stale, 'Proposal is no longer authorized'
      end
      Data.text!(proof['revision'], bytes: 256)
      Data.freeze_tree(proof)
    end

    def respond(metadata:, sender:, displayed:, accept:)
      raise ArgumentError, 'Boolean response required' unless [true, false].include?(accept)
      current = inspect(metadata: metadata, sender: sender)
      raise Stale, 'Displayed proposal changed' unless current.reject{|key,_|key=='accepted'} == displayed.reject{|key,_|key=='accepted'}
      raise Stale, 'Already accepted' if accept && current['metadata']['stage']!='enter' && current['accepted'].include?(@scope['account'])
      raise Unavailable, 'Conditional consent is not connected' unless @backend.respond_to?(:respond_proposal)
      current!
      # The backend rechecks expected_revision and own readiness at the append
      # boundary, then reads back. ELTEN tables do not provide atomic CAS.
      # There is one attempt. This layer never creates a table or retries.
      result = @backend.respond_proposal(notice: current['metadata'], expected_revision: current['revision'], accept: accept)
      current!
      raise TypeError, 'Unsupported proposal response' unless RESPONSES.include?(result)
      raise Stale, 'Proposal changed during response' if result == :conflict
      result
    end

    # UI-side cache guard only. Opening/answering always performs a fresh read.
    def retain_stale_notice?(_metadata,sender:)
      false
    end

    def refresh_on_change?(_metadata,proof:nil)
      true
    end

    def presentable?(proof)
      current!
      proof['window']['opens'] <= @clock.call && @clock.call < proof['window']['closes'] &&
        (proof['metadata']['stage']=='enter' || !proof['accepted'].include?(@scope['account']))
    rescue Unavailable, Stale, Publication::Invalid
      false
    end

    def assert_context!; current!; end
    def expired?(closes); current!; closes<=@clock.call; end
    def remaining_seconds(closes)
      current!
      seconds = closes - @clock.call
      raise Stale, 'Proposal expired' unless seconds.is_a?(Integer) && seconds > 0
      seconds
    end

    private

    def scope
      value = @context && @context.call
      unless value.is_a?(Hash) && value.keys.sort == %w[account account_epoch backend_identity] &&
          value.values.all? { |part| Data.text?(part) && !part.empty? }
        raise Unavailable, 'Authenticated proposal context is unavailable'
      end
      Data.freeze_tree(Data.copy(value.merge('account' => Data.account(value['account']).downcase)))
    end

    def current!
      @changed = true unless scope == @scope
      raise Stale, 'Account or backend changed' if @changed
    rescue Unavailable, Publication::Invalid
      @changed = true
      raise Stale, 'Account or backend unavailable'
    end
  end
end
