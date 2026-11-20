require_relative 'proposal_notice'
require_relative '../game_room_background'
require_relative '../network_errors'

module GameRoomTournaments
  # Drained by the existing extension tick. Reads happen only after a receipt;
  # no polling, automatic consent or table creation. Transient verification
  # failures get a finite read-only retry budget, never an action retry.
  class ProposalNoticeInbox
    LIMIT = 64
    RETRY_DELAYS = [2, 5, 15].freeze
    EMPTY_RESULTS = [].freeze
    attr_reader :last_error
    def initialize(service:, worker:, metadata:ProposalNotice.method(:metadata), clock:-> {Process.clock_gettime(Process::CLOCK_MONOTONIC)})
      @service, @worker = service, worker
      @metadata=metadata
      @clock=clock
      @pending, @seen, @verified, @dismissed = [], {}, {}, {}
      @recheck, @revoked = {}, []
      @retries, @failures = {}, {}
      @closed = false
    end

    def receive(id:, metadata:, sender:)
      return false if @closed || !id.is_a?(Integer) || id <= 0
      notice = @metadata.call(metadata)
      return false if @dismissed.key?(identity(notice))
      sender = Publication::Data.account(sender).downcase
      key = JSON.generate([notice, sender])
      return false if @seen.key?(key)
      return false if @pending.size + @retries.size >= LIMIT
      @seen[key] = true
      @seen.shift while @seen.size > LIMIT * 4
      @pending << [id, notice, sender]
      true
    rescue Publication::Invalid
      false
    end

    def tick
      return EMPTY_RESULTS if @closed
      notices = []
      if (result = @worker.take)
        proof, error = result
        row = @running
        id, metadata, sender = row
        @running = nil
        if @recheck.delete(id)
          @pending << row unless @dismissed.key?(identity(metadata))
        elsif error
          @last_error = error
          missing=error.is_a?(Publication::Invalid) && error.code==:missing_publication
          if error.is_a?(ProposalNotice::Stale) || missing
            unless @service.retain_stale_notice?(metadata,sender:sender)
              @revoked.concat((forget(identity(metadata)) + [id]).uniq)
              @verified.delete(id)
            end
            @failures.delete(id)
          elsif retryable?(error)
            attempt=(@failures[id] || 0)
            if attempt<RETRY_DELAYS.size && @pending.size+@retries.size<LIMIT
              @failures[id]=attempt+1
              delay=GameRoomNetworkErrors.retry_delay(error,normal:RETRY_DELAYS[attempt],rate_limit:30)
              @retries[id]=[row,@clock.call+delay]
            else
              # Redelivery/manual refresh can try again, but idle ticks cannot.
              @seen.delete(JSON.generate([metadata,sender]))
              @failures.delete(id)
            end
          else
            @failures.delete(id)
          end
        elsif !@dismissed.key?(identity(proof.fetch('metadata')))
          first_delivery = !@verified.key?(id)
          @verified[id] = [proof, sender]
          @verified.shift while @verified.size > LIMIT
          notices << [id, proof] if first_delivery
          @failures.delete(id)
        end
      end
      now=@clock.call
      @retries.delete_if do |id,(row,deadline)|
        next false if deadline>now
        @pending << row unless @dismissed.key?(identity(row[1]))
        true
      end
      unless @worker.busy? || @pending.empty?
        row = @pending.first
        started = GameRoomBackground.admit(@worker) { @service.inspect(metadata: row[1], sender: row[2]) }
        if started
          @running = row
          @pending.shift
        end
      end
      notices
    end

    def verified(id); @verified[id]; end
    def dismissed?(token); @dismissed.key?(token); end

    # The extension keeps its one-second cadence, but a configured inbox with
    # no receipt, retry, worker result or revocation has nothing to drain. An
    # admitted worker always owns @running before this extension tick returns.
    def work_pending?
      !@closed && (@running != nil || !@pending.empty? || !@retries.empty? ||
        !@revoked.empty?)
    end

    # A verified tournament change wakes a finite read, never a timer poll.
    # If verification was already in flight, its earlier snapshot cannot
    # restore an invitation cancelled while that read was running.
    def refresh(reference)
      return if @closed
      @verified.each do |id,(proof,sender)|
        next unless proof.dig('metadata','publication_ref') == reference
        next unless @service.refresh_on_change?(proof['metadata'],proof:proof)
        next if @pending.any?{|row|row.first==id} || @retries.key?(id) || @pending.size+@retries.size>=LIMIT
        if @running && @running.first==id
          @recheck[id]=true
        else
          @pending << [id,proof['metadata'],sender]
        end
      end
      if @running && @running[1]['publication_ref']==reference && @service.refresh_on_change?(@running[1])
        @recheck[@running.first]=true
      end
    end

    def take_revoked
      return EMPTY_RESULTS if @revoked.empty?
      ids, @revoked = @revoked.uniq, []
      ids
    end
    def forget(token)
      return [] unless token.is_a?(String) && !token.empty?
      @dismissed[token]=true
      @dismissed.shift while @dismissed.size>LIMIT*4
      ids=@verified.filter_map{|id,(proof,_)|id if identity(proof.fetch('metadata'))==token}
      ids.each{|id|@verified.delete(id)}
      @pending.reject!{|_,metadata,_|identity(metadata)==token}
      @retries.delete_if do |id,(row,_)|
        next false unless identity(row[1])==token
        @failures.delete(id)
        true
      end
      ids
    end
    def pending
      @verified.filter_map do |id,(proof,sender)|
        {tournament_invitation:proof['metadata'],sender:sender,notification_id:id,players:proof['players']} if @service.presentable?(proof)
      end
    end
    def close
      @closed = true
      @pending.clear
      @verified.clear
      @seen.clear
      @dismissed.clear
      @recheck.clear
      @revoked.clear
      @retries.clear
      @failures.clear
      @worker.close
    end

    private

    def identity(metadata)
      metadata['token'] || metadata.fetch('event_id')
    end

    def retryable?(error)
      return false if GameRoomNetworkErrors.cancelled?(error)
      error.is_a?(IOError) || error.is_a?(SystemCallError) || GameRoomNetworkErrors.transient?(error)
    end
  end
end
