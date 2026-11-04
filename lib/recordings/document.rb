require 'json'
require 'securerandom'
require 'time'
require 'digest'

module GameRoomRecordings
  class Invalid < StandardError; end
  class Unavailable < StandardError; end
  class UserMessage < Unavailable; end

  # Passive presentation data only. These files are never game archives,
  # commands, Ruby objects, controller credentials or authoritative results.
  module Document
    FORMAT = 'power-games-recording'.freeze
    VERSION = 1
    TEXT_MAGIC = 'Power Games'.freeze
    MAX_BYTES = 128 * 1024 * 1024
    MAX_EVENTS = 750_000
    MAX_DURATION = 7 * 24 * 60 * 60 * 1000
    UUID = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/
    KINDS = %w[frame audio].freeze
    AUDIO_METHODS = %w[reset start_match goal point prepare stop_ball announce announce_set hurry].freeze
    SCENE_METHODS = %w[reset goal point prepare stop_ball].freeze

    class ObjectMap < Hash
      def []=(key,value)
        raise Invalid,'Duplicate recording field' if key?(key)
        super
      end
    end

    module_function

    def copy(value)
      case value
      when Hash then value.to_h { |key,item| [key.to_s,copy(item)] }
      when Array then value.map { |item| copy(item) }
      when String then value.dup.force_encoding(Encoding::UTF_8)
      when Integer, TrueClass, FalseClass, NilClass then value
      when Float
        raise Invalid,'Non-finite recording value' unless value.finite?
        value
      else raise Invalid,'Unsupported recording value'
      end
    end

    def metadata(game:, game_name:, players:, options: {}, build: nil, seat: nil, complete_start: true, now: Time.now)
      {'id'=>SecureRandom.uuid,'game'=>game.to_s,'game_name'=>game_name.to_s,
        'title'=>game_name.to_s,'players'=>players.map(&:to_s),'options'=>copy(options),
        'recorded_at'=>now.to_i,'build'=>build.to_s,'seat'=>seat,
        'complete_start'=>complete_start,'complete_end'=>false,'duration_ms'=>0}
    end

    def header(metadata)
      {'format'=>FORMAT,'version'=>VERSION,'metadata'=>metadata}
    end

    def validate_header(value)
      raise Invalid,'Unsupported recording format' unless value.is_a?(Hash) && value['format']==FORMAT && value['version']==VERSION
      meta=value['metadata']
      raise Invalid,'Invalid recording description' unless meta.is_a?(Hash) && UUID.match?(meta['id'].to_s) &&
        %w[axel_pong audio_ball].include?(meta['game']) && text?(meta['game_name'],256) && text?(meta['title'],512) &&
        meta['players'].is_a?(Array) && [2,4].include?(meta['players'].size) && meta['players'].all? { |name| text?(name,256) } &&
        meta['recorded_at'].is_a?(Integer) && meta['recorded_at'].positive? && meta['options'].is_a?(Hash) &&
        JSON.generate(meta['options']).bytesize<=16_384 && text?(meta['build'],64,empty:true) &&
        (meta['seat'].nil? || integer?(meta['seat'],0,meta['players'].size-1)) &&
        [true,false].include?(meta['complete_start']) && [true,false].include?(meta['complete_end']) &&
        integer?(meta['duration_ms'],0,MAX_DURATION)
      value
    end

    def validate(value)
      validate_header(value)
      events=value['timeline']
      raise Invalid,'Invalid recording timeline' unless events.is_a?(Array) && events.size.between?(1,MAX_EVENTS)
      prior=0
      events.each do |event|
        raise Invalid,'Invalid recording event' unless event.is_a?(Hash) && event.keys.sort==%w[data kind t] &&
          integer?(event['t'],prior,value['metadata']['duration_ms']) && KINDS.include?(event['kind']) && event['data'].is_a?(Hash)
        prior=event['t']
        data=event['data']
        if event['kind']=='frame'
          validate_frame(data,value['metadata'])
        else
          validate_audio(data,value['metadata'])
        end
      end
      raise Invalid,'Recording has no scene' unless events.any? { |event| event['kind']=='frame' }
      value
    end

    def validate_audio(data,meta)
      method=data['method']; args=data['args']; keys=data['kwargs']
      raise Invalid,'Invalid recording sound event' unless AUDIO_METHODS.include?(method) && args.is_a?(Array) && keys.is_a?(Hash) &&
        JSON.generate(data).bytesize<=16_384
      case method
      when 'reset','start_match'
        raise Invalid,'Invalid recording sound event' unless args.empty? && keys.empty?
      when 'prepare','stop_ball'
        raise Invalid,'Invalid recording side' unless args.size==1 && integer?(args[0],0,1) && keys.keys==['viewer']
      when 'announce','hurry'
        raise Invalid,'Invalid recording text' unless args.size==1 && text?(args[0],4096) && keys.empty?
      when 'announce_set'
        raise Invalid,'Invalid recording set' unless args.size==1 && integer?(args[0],1,100_000) && keys.empty?
      when 'goal','point'
        allowed=if method=='goal'
          meta['game']=='audio_ball' ? %w[viewer winner reason] : %w[viewer winner]
        elsif meta['game']=='audio_ball'
          %w[viewer winner finished goal_at sets set_finished]
        else
          %w[viewer winner finished goal_at score_text result_text]
        end
        raise Invalid,'Invalid recording sound options' unless (keys.keys-allowed).empty? &&
          keys.key?('viewer') &&
          (keys['winner'].nil? || integer?(keys['winner'],0,1)) &&
          (keys['goal_at'].nil? || number?(keys['goal_at'],0,MAX_DURATION/1000.0)) &&
          %w[finished set_finished].all? { |key| !keys.key?(key) || [true,false].include?(keys[key]) } &&
          %w[score_text result_text].all? { |key| keys[key].nil? || text?(keys[key],4096,empty:true) }
        raise Invalid,'Invalid recording goal reason' unless keys['reason'].nil? || %w[miss wrong_turn timeout].include?(keys['reason'])
        if method=='point'
          raise Invalid,'Invalid recorded score' unless args.size==1 && pair?(args[0])
          if meta['game']=='audio_ball'
            raise Invalid,'Invalid recorded sets' unless pair?(keys['sets']) && keys.key?('set_finished') && keys.key?('winner') && keys.key?('finished')
          end
        else
          raise Invalid,'Invalid recording goal' unless args.empty? && (meta['game']!='audio_ball' || keys.key?('winner'))
        end
      end
      if keys.key?('viewer')
        raise Invalid,'Invalid recording perspective' unless keys['viewer'].nil? || integer?(keys['viewer'],0,3)
      end
      true
    end

    def validate_frame(data,meta)
      state=data['snapshot']
      raise Invalid,'Invalid recording frame' unless state.is_a?(Hash) && [true,false].include?(data['paused']) &&
        integer?(data['rally'],0,10_000_000) && integer?(data['generation'],0,10_000_000) &&
        pair?(data['scores']) && pair?(data['sets']) && integer?(data['set_number'],1,100_000)
      if meta['game']=='axel_pong'
        raise Invalid,'Invalid Pong recording scene' unless state['p'].is_a?(Array) && state['p'].length==meta['players'].length &&
          state['p'].all? { |n| number?(n,-1000,1000) } && state['b'].is_a?(Hash) &&
          %w[x y dx dy].all? { |key| number?(state['b'][key],-1_000_000,1_000_000) } &&
          state['fx'].is_a?(Array) && state['fx'].size<=64 && state['fx'].all? { |fx|
            fx.is_a?(Array) && fx.size==5 && integer?(fx[0],0,2**53) && text?(fx[1],64) &&
              (fx[2].nil? || integer?(fx[2],0,3)) && number?(fx[3],-1_000_000,1_000_000) && number?(fx[4],-1_000_000,1_000_000)
          } && state['shields'].is_a?(Array) && state['shields'].length==meta['players'].length &&
          state['shields'].all? { |n| number?(n,0,1_000_000) }
        raise Invalid,'Invalid Pong recording controls' unless [true,false].include?(state['invisible']) &&
          integer?(state['server'],0,meta['players'].size-1) && state['edges'].is_a?(Array) && state['edges'].size==meta['players'].size &&
          state['edges'].all? { |n| integer?(n,0,2**53) }
        if meta['players'].length==4
          raise Invalid,'Invalid Pong recording teams' unless teams?(state['teams'])
        end
      else
        raise Invalid,'Invalid Audio Ball recording scene' unless %w[waiting prepared flying over].include?(state['phase']) &&
          number?(state['position'],0,1000) && integer?(state['turn'],0,2**53) &&
          (state['shot'].nil? || %w[up left down].include?(state['shot']))
      end
      raise Invalid,'Invalid recording goal' unless state['goal'].nil? || integer?(state['goal'],0,meta['players'].length-1)
      true
    end

    def parse(bytes)
      raise Invalid,'The recording is too large' if bytes.bytesize>MAX_BYTES
      validate(copy(JSON.parse(bytes,max_nesting:16,allow_nan:false,object_class:ObjectMap)))
    rescue JSON::ParserError, EncodingError, TypeError, ArgumentError, SystemStackError
      raise Invalid,'The recording is damaged or unsupported'
    end

    def text_header(game_name:, players:, now: Time.now)
      [TEXT_MAGIC,game_name.to_s.gsub(/[\r\n]/,' '),now.iso8601,players.join(', '),''].join("\r\n")+"\r\n"
    end

    def text_metadata(bytes)
      text=bytes.dup.force_encoding(Encoding::UTF_8)
      raise Invalid,'Invalid text history' unless text.valid_encoding?
      lines=text.lines.first(5).map(&:strip)
      raise Invalid,'Not a Power Games history' unless lines[0]==TEXT_MAGIC && text?(lines[1],512) && text?(lines[2],64)
      at=Time.iso8601(lines[2])
      {'game'=>'text','game_name'=>lines[1],'title'=>lines[1],'recorded_at'=>at.to_i,
        'players'=>lines[3].to_s.split(', ').reject(&:empty?),'duration_ms'=>nil}
    rescue ArgumentError
      raise Invalid,'Not a Power Games history'
    end

    def text?(value,bytes,empty:false)
      value.is_a?(String) && value.valid_encoding? && value.bytesize<=bytes && (empty || !value.empty?) && !value.include?("\0")
    end
    def integer?(value,minimum,maximum); value.is_a?(Integer) && value.between?(minimum,maximum); end
    def number?(value,minimum,maximum); value.is_a?(Numeric) && value.finite? && value.between?(minimum,maximum); end
    def pair?(value); value.is_a?(Array) && value.size==2 && value.all? { |n| integer?(n,0,10_000_000) }; end
    def teams?(value); value.is_a?(Array) && value.size==4 && value.sort==[0,0,1,1]; end
  end
end
