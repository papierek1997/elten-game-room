require 'tmpdir'
require 'zip'
require 'uri'
require_relative 'library'
require_relative '../game_room_localization'
require_relative '../game_content'

module GameRoomRecordings
  class Delivery
    using GameRoomLocalization::Translations
    SUBJECT='Power Games replay'.freeze
    MARKER='Power-Games-Recording:'.freeze
    MAX_ATTACHMENT=4*1024*1024

    # Native typed social modules do not themselves forward task options.
    class RequestClient
      attr_accessor :before_message
      def initialize(client,token,check);@client,@token,@check=client,token,check;end
      def api_data(method,path,params=nil)
        @check.call;@token&.raise_if_cancelled!
        @before_message&.call if method=='POST' && path=='/api/v1/messages'
        result=@client.api_data(method,path,params,timeout:20,cancellation_token:@token)
        @check.call;result
      end
      def api_payload(method,path,params=nil)
        @check.call;@token&.raise_if_cancelled!
        result=@client.api_payload(method,path,params,timeout:20,cancellation_token:@token)
        @check.call;result
      end
      def api_binary_data(method,path,body,headers={},params=nil)
        @check.call;@token&.raise_if_cancelled!
        result=@client.api_binary_data(method,path,body,headers,params,timeout:45,cancellation_token:@token)
        @check.call;result
      end
      def api_download(path)
        @check.call;@token&.raise_if_cancelled!
        result=@client.api_download(path,timeout:45,cancellation_token:@token)
        @check.call;result
      end
    end

    def initialize(library,client:nil,messages:nil,attachments:nil)
      @library=library
      @client=client || EltenLink::Client.new
      @messages=messages || EltenLink::Messages
      @attachments=attachments || EltenLink::Attachments
    end

    def send_file(name,recipient:,token:nil)
      check=-> { @library.check! }
      client=RequestClient.new(@client,token,check)
      bytes=@library.read(name)
      digest=Digest::SHA256.hexdigest(bytes)
      raise Invalid,'Invalid recording recipient' unless recipient.is_a?(String) && /\A[^\s\x00\r\n\/\\]{1,64}\z/.match?(recipient)
      key=Digest::SHA256.hexdigest([recipient.downcase,digest].join("\0"))
      state=@library.delivery_state(key)
      if state
        validate_state(state,recipient,digest)
        if state['status']=='sent' && !state['cleanup_pending']
          state=nil # A new explicit send after a completed send is intentional.
        end
      end
      unless state
        state={'version'=>1,'id'=>SecureRandom.uuid,'recipient'=>recipient,'sha256'=>digest,
          'extension'=>File.extname(name).downcase,'status'=>'prepared','cleanup_pending'=>true}
        @library.write_delivery(key,state)
      end
      if state['status']=='attempted'
        found=matching_messages(client,state)
        raise UserMessage,_('Sending has not been confirmed. Try again to check delivery; the file will not be sent twice.') if found.empty?
        state['status']='sent'
        @library.write_delivery(key,state)
      end
      if state['status']=='prepared'
        Dir.mktmpdir('power-games-replay-send-') do |directory|
          path=File.join(directory,filename(state))
          File.binwrite(path,bytes)
          if bytes.bytesize>MAX_ATTACHMENT
            state['extension']+='.zip'
            path=File.join(directory,filename(state))
            Zip::File.open(path,create:true) { |zip| zip.get_output_stream('recording'+File.extname(name)) { |io| io.write(bytes) } }
          end
          raise UserMessage,_('This replay is too large to send as a message attachment. Export the file to share it another way.') if File.size(path)>MAX_ATTACHMENT
          message=body(state,name)
          @library.check!
          # Upload/preparation failures are retryable. Only crossing the native
          # message POST makes delivery uncertain and must be journalled first.
          client.before_message=-> {state['status']='attempted';@library.write_delivery(key,state)}
          result=@messages.send_text(client,to:recipient,subject:subject(state),text:message,attachments:[path])
          raise UserMessage,_('Sending has not been confirmed. Try again to check delivery; the file will not be sent twice.') unless result==true
          @library.check!
          state['status']='sent'
          @library.write_delivery(key,state)
        end
      end
      removed=remove_sender_copy(client,state)
      state['cleanup_pending']=!removed
      @library.write_delivery(key,state)
      {sent:true,removed:removed}
    end

    def incoming(token:nil)
      client=RequestClient.new(@client,token,-> { @library.check! })
      result=@messages.search_messages(client,MARKER)
      raise Unavailable,'Recording message list unavailable' unless result.respond_to?(:messages)
      result.messages.filter_map do |message|
        next unless message.receiver.to_s.casecmp?(@library.account) && !message.sender.to_s.casecmp?(@library.account)
        reference(message)
      end.sort_by { |row| [-row['date'],row['message_id']] }
    end

    def receive(ref,token:nil)
      client=RequestClient.new(@client,token,-> { @library.check! })
      message=fresh_message(client,ref)
      info=@attachments.info(client,message.attachments.first)
      raise Invalid,'Invalid recording attachment' unless info && info.id.to_s==ref['attachment'].to_s && info.name==ref['filename'] &&
        info.size.is_a?(Integer) && info.size.between?(1,MAX_ATTACHMENT)
      url=@attachments.download_url(info.id)
      bytes=client.api_download(URI.parse(url).request_uri)
      raise Invalid,'Invalid recording attachment size' unless bytes.bytesize==info.size && bytes.bytesize<=MAX_ATTACHMENT
      extension=File.extname(ref['filename']).downcase
      if extension=='.zip'
        bytes,extension=unpack(bytes)
      end
      raise Invalid,'Recording attachment checksum mismatch' unless Digest::SHA256.hexdigest(bytes)==ref['sha256']
      extension=='.json' ? Document.parse(bytes) : Document.text_metadata(bytes)
      {bytes:bytes,extension:extension}
    end

    def remove_received(ref,token:nil)
      client=RequestClient.new(@client,token,-> { @library.check! })
      message=fresh_message(client,ref)
      @messages.delete_message(client,message.id)
      @library.check!
      true
    end

    private

    def validate_state(state,recipient,digest)
      raise Invalid,'Invalid replay delivery journal' unless state['version']==1 && Document::UUID.match?(state['id'].to_s) &&
        state['recipient'].to_s.casecmp?(recipient) && state['sha256']==digest &&
        %w[.json .txt .json.zip .txt.zip].include?(state['extension']) &&
        %w[prepared attempted sent].include?(state['status']) && [true,false].include?(state['cleanup_pending'])
    end

    def subject(state); "#{SUBJECT} [#{state.fetch('id')}]"; end
    def filename(state); "power-games-recording-#{state.fetch('id')}#{state.fetch('extension')}"; end

    def body(state,name)
      row=@library.list.find { |entry| entry['filename']==name }
      [row && row['title'],row && row['players'].join(', '),
        GameRoomContent.utf8(_('Open Power Games, then Saved games, Histories and replays, and Import from messages.')),
        "#{MARKER} #{state['id']}","File-SHA256: #{state['sha256']}"].compact.join("\r\n")
    end

    def reference(message)
      id=message.text.to_s[/^#{Regexp.escape(MARKER)} ([0-9a-f-]{36})\r?$/,1]
      sha=message.text.to_s[/^File-SHA256: ([0-9a-f]{64})\r?$/,1]
      return unless Document::UUID.match?(id.to_s) && sha && message.subject=="#{SUBJECT} [#{id}]" &&
        message.id.to_i.positive? && message.attachments.to_a.size==1
      names=message.attachments_names.to_a
      return unless names.size==1 && /\Apower-games-recording-#{Regexp.escape(id)}\.(?:json|txt)(?:\.zip)?\z/.match?(names[0].to_s)
      {'id'=>id,'sha256'=>sha,'message_id'=>message.id.to_i,'sender'=>message.sender.to_s,
        'subject'=>message.subject.to_s,'filename'=>names[0],'attachment'=>message.attachments[0],
        'date'=>message.date.to_i,'description'=>message.text.to_s.lines.first.to_s.strip[0,512]}
    end

    def fresh_message(client,ref)
      rows=@messages.messages(client,user:ref.fetch('sender'),subject:ref.fetch('subject'),limit:20)
      raise Unavailable,'Recording message unavailable' unless rows.respond_to?(:messages)
      found=rows.messages.find { |message| message.id.to_i==ref['message_id'] && message.receiver.to_s.casecmp?(@library.account) && reference(message)==ref }
      raise Unavailable,'The recording message has changed or was removed' unless found
      found
    end

    def matching_messages(client,state)
      result=@messages.messages(client,user:state.fetch('recipient'),subject:subject(state),limit:20)
      raise Unavailable,'Recording delivery status unavailable' unless result.respond_to?(:messages) && result.respond_to?(:more) && !result.more
      result.messages.select do |message|
        message.sender.to_s.casecmp?(@library.account) && message.receiver.to_s.casecmp?(state['recipient']) &&
          message.subject==subject(state) && message.text.to_s.lines.any? { |line| line.strip=="#{MARKER} #{state['id']}" } &&
          message.text.to_s.lines.any? { |line| line.strip=="File-SHA256: #{state['sha256']}" } &&
          message.attachments.to_a.size==1 && message.attachments_names.to_a==[filename(state)]
      end
    end

    def remove_sender_copy(client,state)
      return true if state['recipient'].casecmp?(@library.account)
      matching_messages(client,state).each { |message| @messages.delete_message(client,message.id) }
      true
    rescue StandardError=>error
      Log.warning("Power Games sent replay cleanup failed: #{error.class}: #{error.message}") if defined?(Log)
      false
    end

    def unpack(bytes)
      result=nil
      Zip::File.open_buffer(bytes) do |zip|
        entries=zip.entries
        raise Invalid,'Invalid replay archive' unless entries.size==1 && %w[recording.json recording.txt].include?(entries[0].name) &&
          !entries[0].directory? && entries[0].size.between?(1,Document::MAX_BYTES)
        data=entries[0].get_input_stream.read(Document::MAX_BYTES+1)
        raise Invalid,'Invalid replay archive size' unless data.bytesize==entries[0].size && data.bytesize<=Document::MAX_BYTES
        result=[data,File.extname(entries[0].name)]
      end
      result
    rescue Zip::Error
      raise Invalid,'Invalid replay archive'
    end
  end
end
