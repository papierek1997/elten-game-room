require 'fileutils'
require_relative 'document'

module GameRoomRecordings
  # The directory, not an index of arbitrary external paths, owns the library.
  # All methods touching paths/files run on a finite background task.
  class Library
    attr_reader :account
    def initialize(program, account:, current_account:)
      @program,@account,@current_account=program,account.to_s.downcase,current_account
    end

    def root
      check!
      @root ||= File.expand_path(@program.data_path("recordings/#{Digest::SHA256.hexdigest(@account)}"))
      FileUtils.mkdir_p(@root)
      raise Invalid,'Unsafe recording folder' if File.lstat(@root).symlink?
      @root
    end

    def list
      check!
      Dir.children(root).filter_map do |name|
        next unless %w[.json .txt].include?(File.extname(name).downcase)
        path=owned_path(name)
        next unless File.file?(path)
        begin
          meta=description(path)
          meta.merge('filename'=>name,'kind'=>File.extname(name).downcase=='.txt' ? 'text' : 'audio')
        rescue Invalid,JSON::ParserError,ArgumentError,EncodingError
          {'filename'=>name,'kind'=>'damaged','title'=>name,'recorded_at'=>File.mtime(path).to_i,'players'=>[]}
        end
      rescue Errno::ENOENT
        nil # A manual removal during the scan is just a missing library file.
      end.sort_by { |row| [-row['recorded_at'],row['filename']] }
    end

    def description(path)
      stat=safe_file!(path)
      raise Invalid,'The recording is too large' if stat.size>Document::MAX_BYTES
      File.open(path,'rb') do |file|
        prefix=file.gets(16_385).to_s.force_encoding(Encoding::UTF_8)
        if File.extname(path).downcase=='.txt'
          file.rewind
          header=5.times.map { file.gets(16_385).to_s }.join
          Document.text_metadata(header)
        elsif prefix.end_with?("\n") && prefix.rstrip.end_with?(',')
          Document.validate_header(JSON.parse(prefix.rstrip.delete_suffix(',')+'}',max_nesting:16)).fetch('metadata')
        else
          Document.parse(File.binread(path)).fetch('metadata')
        end
      end
    end

    def read(name)
      path=owned_path(name)
      size=safe_file!(path).size
      raise Invalid,'The recording is too large' if size>Document::MAX_BYTES
      bytes=File.binread(path)
      File.extname(name).downcase=='.txt' ? Document.text_metadata(bytes) : Document.parse(bytes)
      check!
      bytes
    end

    def save_document(value)
      Document.validate(value)
      bytes=JSON.generate(Document.header(value.fetch('metadata'))).delete_suffix('}')+",\n\"timeline\":[\n"+
        value.fetch('timeline').map { |row| JSON.generate(row) }.join(",\n")+"\n]}\n"
      save_bytes(bytes,extension:'.json')
    end

    def save_text(entries,game_name:,players:[],now:Time.now)
      bytes=Document.text_header(game_name:game_name,players:players,now:now)+entries.to_a.map do |entry|
        text=entry.respond_to?(:text) ? entry.text : entry
        text.to_s.dup.force_encoding(Encoding::UTF_8).encode(Encoding::UTF_8,invalid: :replace,undef: :replace).gsub(/\r\n?/,"\n").sub(/\n+\z/,'')
      end.join("\n").gsub("\n","\r\n")+"\r\n"
      save_bytes(bytes,extension:'.txt')
    end

    def import(path)
      extension=File.extname(path).downcase
      raise Invalid,'Unsupported recording file' unless %w[.json .txt].include?(extension)
      raise Invalid,'The recording is too large' if safe_file!(path).size>Document::MAX_BYTES
      bytes=File.binread(path)
      import_bytes(bytes,extension:extension)
    end

    def import_bytes(bytes,extension:)
      meta=extension=='.json' ? Document.parse(bytes).fetch('metadata') : Document.text_metadata(bytes)
      existing=list.find do |row|
        row['kind']!='damaged' && File.extname(row['filename']).downcase==extension &&
          (!meta['id'] || row['id']==meta['id']) && Digest::SHA256.hexdigest(read(row['filename']))==Digest::SHA256.hexdigest(bytes)
      end
      return existing['filename'] if existing
      save_bytes(bytes,extension:extension)
    end

    def delivery_state(key)
      path=delivery_path(key)
      return nil unless File.exist?(path)
      raise Invalid,'Invalid replay delivery journal' if safe_file!(path).size>32_768
      value=JSON.parse(File.binread(path),max_nesting:8)
      raise Invalid,'Invalid replay delivery journal' unless value.is_a?(Hash)
      value
    rescue JSON::ParserError
      raise Invalid,'Invalid replay delivery journal'
    end

    def write_delivery(key,value)
      raise Invalid,'Invalid replay delivery journal' unless value.is_a?(Hash) && JSON.generate(value).bytesize<=32_768
      atomic_replace(delivery_path(key),JSON.generate(value))
    end

    def export(name,directory)
      bytes=read(name)
      destination=File.expand_path(directory)
      raise Invalid,'Choose a different export folder' if destination.casecmp?(root)
      path=File.join(destination,File.basename(name))
      exclusive_write(path,bytes)
      path
    end

    def rename(name,title)
      raise Invalid,'Invalid recording title' unless Document.text?(title,512) && !title.match?(/[\r\n]/)
      bytes=read(name)
      if File.extname(name).downcase=='.json'
        value=Document.parse(bytes)
        value['metadata']['title']=title
        bytes=JSON.generate(Document.header(value.fetch('metadata'))).delete_suffix('}')+",\n\"timeline\":[\n"+
          value['timeline'].map { |row| JSON.generate(row) }.join(",\n")+"\n]}\n"
      else
        lines=bytes.dup.force_encoding(Encoding::UTF_8).split(/\r?\n/,-1)
        lines[1]=title
        bytes=lines.join("\r\n")
      end
      atomic_replace(owned_path(name),bytes)
      name
    end

    def delete(name)
      path=owned_path(name)
      safe_file!(path)
      # A single explicitly selected owned file, never an external import path.
      File.delete(path)
      true
    end

    def check!
      raise Unavailable,'The signed-in account has changed' if @account.empty? || @current_account.call.to_s.downcase!=@account
    end

    private

    def delivery_path(key)
      raise Invalid,'Unsafe replay delivery key' unless /\A[0-9a-f]{64}\z/.match?(key.to_s)
      directory=File.join(root,'.delivery')
      FileUtils.mkdir_p(directory)
      raise Invalid,'Unsafe replay delivery folder' if File.lstat(directory).symlink?
      path=File.join(directory,"#{key}.json")
      safe_file!(path) if File.exist?(path) || File.symlink?(path)
      path
    end

    def owned_path(name)
      check!
      raise Invalid,'Unsafe recording name' unless name.is_a?(String) && File.basename(name)==name && !name.match?(/[\\\/\x00:]/) && name!='.' && name!='..'
      path=File.expand_path(File.join(root,name))
      raise Invalid,'Unsafe recording path' unless File.dirname(path)==root
      safe_file!(path) if File.exist?(path) || File.symlink?(path)
      path
    end

    def safe_file!(path)
      stat=File.lstat(path)
      raise Invalid,'Unsafe recording file' if stat.symlink? || !stat.file? || stat.nlink>1
      stat
    end

    def save_bytes(bytes,extension:)
      raise Invalid,'The recording is too large' if bytes.bytesize>Document::MAX_BYTES
      raise Invalid,'Unsupported recording file' unless %w[.json .txt].include?(extension)
      name="recording-#{SecureRandom.uuid}#{extension}"
      path=owned_path(name)
      atomic_replace(path,bytes)
      name
    end

    def atomic_replace(path,bytes)
      check!
      temp=path+".#{SecureRandom.hex(8)}.tmp"
      exclusive_write(temp,bytes)
      check!
      File.rename(temp,path)
    ensure
      File.delete(temp) if temp && File.file?(temp)
    end

    def exclusive_write(path,bytes)
      created=false
      File.open(path,File::WRONLY|File::CREAT|File::EXCL|File::BINARY,0o600) do |file|
        created=true
        file.write(bytes)
        file.flush
        file.fsync
      end
    rescue Exception
      File.delete(path) if created && File.file?(path)
      raise
    end
  end
end
