module GameRoomStatistics
  class QueueError < StandardError; end
  class QueueFull < QueueError; end
  class InvalidQueueData < QueueError; end
  class InvalidQueueState < QueueError; end
  class ConflictingPayload < InvalidQueueData; end

  class Queue
    PATH = "statistics-pending.json".freeze
    MAX_PENDING = 4096
    MAX_ACKNOWLEDGED = 2048

    def initialize(storage:, user:)
      @storage, @user = storage, copy_user(user).freeze
    end

    def push(key, payload)
      key = copy_key(key)
      payload = copy_payload(payload)
      added = false
      update_state do |state|
        account = state["accounts"][@user] ||= {"pending" => {}, "acknowledged" => {}}
        previous = account["pending"][key] || account["acknowledged"][key]
        if previous
          raise ConflictingPayload, "Statistics queue key has a different payload" unless previous.eql?(payload)
        else
          raise QueueFull, "Statistics pending queue is full" if account["pending"].size >= MAX_PENDING
          account["pending"][key] = payload
          added = true
        end
      end
      added
    end

    def acknowledge(entries)
      raise InvalidQueueData, "Statistics acknowledgement must be an array" unless entries.instance_of?(Array)
      entries = entries.map do |entry|
        unless entry.instance_of?(Array) && entry.size == 2
          raise InvalidQueueData, "Statistics acknowledgement entries must be key/payload pairs"
        end
        [copy_key(entry[0]), copy_payload(entry[1])]
      end
      removed = 0
      update_state do |state|
        account = state["accounts"][@user]
        next unless account
        entries.each do |key, payload|
          next unless account["pending"][key].eql?(payload)
          account["pending"].delete(key)
          account["acknowledged"][key] = payload
          account["acknowledged"].shift while account["acknowledged"].size > MAX_ACKNOWLEDGED
          removed += 1
        end
      end
      removed
    end

    def batch(limit: 50)
      unless limit.instance_of?(Integer) && limit.between?(0, MAX_PENDING)
        raise InvalidQueueData, "Statistics batch limit must be an integer from 0 to 4096"
      end
      state = @storage.read_json(PATH, default: {"version" => 1, "accounts" => {}})
      validate_state(state)
      account = state["accounts"][@user]
      return [] unless account
      account["pending"].first(limit).map { |key, payload| [copy_key(key), copy_payload(payload)] }
    end

    def pending?
      size > 0
    end

    def size
      batch(limit: MAX_PENDING).size
    end

    private

    def update_state
      result = @storage.update_json(PATH, default: {"version" => 1, "accounts" => {}}) do |state|
        validate_state(state)
        yield state
      end
      raise IOError, "Statistics queue storage did not confirm the write" unless result.instance_of?(Hash)
    end

    def exact_fields?(value, fields)
      value.instance_of?(Hash) && value.size == fields.size && fields.all? { |field| value.key?(field) }
    end

    def validate_state(state)
      unless exact_fields?(state, %w[version accounts]) && state["version"].eql?(1) && state["accounts"].instance_of?(Hash)
        raise InvalidQueueState, "Invalid statistics queue root"
      end
      state["accounts"].each do |user, account|
        copy_user(user)
        unless exact_fields?(account, %w[pending acknowledged])
          raise InvalidQueueState, "Invalid statistics queue account"
        end
        {"pending" => MAX_PENDING, "acknowledged" => MAX_ACKNOWLEDGED}.each do |field, limit|
          rows = account[field]
          unless rows.instance_of?(Hash) && rows.size <= limit
            raise InvalidQueueState, "Invalid statistics queue entries or capacity"
          end
          rows.each { |key, payload| copy_key(key); copy_payload(payload) }
        end
        if account["pending"].any? { |key, _payload| account["acknowledged"].key?(key) }
          raise InvalidQueueState, "Statistics entry is both pending and acknowledged"
        end
      end
      state
    rescue InvalidQueueData
      raise InvalidQueueState, "Statistics queue contains invalid stored data"
    end

    def copy_string(value)
      raise InvalidQueueData, "Statistics queue strings must be plain strings" unless value.instance_of?(String)
      raise InvalidQueueData, "Statistics queue string has invalid encoding" unless value.valid_encoding?
      String.new(value).encode(Encoding::UTF_8)
    rescue EncodingError
      raise InvalidQueueData, "Statistics queue string has invalid encoding"
    end

    def copy_user(user)
      user = copy_string(user)
      raise InvalidQueueData, "Statistics queue requires a signed-in account" if user.strip.empty?
      user
    end

    def copy_key(key)
      key = copy_string(key)
      raise InvalidQueueData, "Statistics queue key must contain 1 to 160 characters" unless key.length.between?(1, 160)
      key
    end

    def copy_payload(payload)
      raise InvalidQueueData, "Statistics queue payload must be a plain object" unless payload.instance_of?(Hash)
      payload.each_with_object({}) do |(key, value), result|
        field = copy_string(key)
        if value.instance_of?(String)
          value = copy_string(value)
        elsif ![Integer, Float, TrueClass, FalseClass, NilClass].any? { |type| value.instance_of?(type) } ||
            (value.instance_of?(Float) && !value.finite?)
          raise InvalidQueueData, "Statistics queue payload values must be finite JSON scalars"
        end
        result[field] = value
      end
    end
  end
end
