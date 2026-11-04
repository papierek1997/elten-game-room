require_relative 'document'

module GameRoomRecordings
  # Parsing, validation and timeline indexes run together on a finite worker.
  # The UI only receives an immutable passive document, never executable data.
  class Prepared
    attr_reader :document,:frames,:points,:sets,:actions,:markers,:match_start_index
    def self.load(bytes); new(Document.parse(bytes)); end
    def self.copy(document); new(Document.validate(Document.copy(document))); end

    def initialize(document)
      @document=document
      events=document.fetch('timeline')
      @frames=[];@points=[];@sets=[];@actions=[]
      seen={}
      events.each_with_index do |event,index|
        if event['kind']=='audio'
          method=event.dig('data','method')
          if method=='start_match'
            next unless @match_start_index.nil?
            @match_start_index=index
          end
          if method=='point'
            @points << index
            @sets << index if event.dig('data','kwargs','set_finished')==true
          end
          @actions << index unless method=='reset'
        else
          @frames << index
          fresh=event['data']['snapshot'].fetch('fx',[]).map do |effect|
            key=[event['data']['generation'],effect[0]]
            first=!seen[key];seen[key]=true
            first && %w[serve hit wall shield_hit shield_on shield_off invisible].include?(effect[1])
          end
          @actions << index if fresh.any?
        end
      end
      @markers={point:@points,set:@sets,action:@actions}.transform_values do |indexes|
        ([0]+indexes.map { |i| events[i]['t'] }).uniq.freeze
      end.freeze
      freeze_data(@document)
      [@frames,@points,@sets,@actions].each(&:freeze)
      freeze
    end
    private_class_method :new

    def [](key); @document[key]; end

    private

    def freeze_data(value)
      case value
      when Hash then value.each { |key,item| key.freeze;freeze_data(item) }
      when Array then value.each { |item| freeze_data(item) }
      end
      value.freeze
    end
  end
end
