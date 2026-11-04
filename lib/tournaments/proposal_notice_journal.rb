require_relative 'proposal_notice'
require_relative 'strict_json'
require_relative 'local_filesystem'

module GameRoomTournaments
  # Keep the host's atomic JSON write, but never use its corrupt-file fallback.
  # The file lock spans the entire host transaction, including its final write.
  class ProposalNoticeJournal
    MAX_BYTES = 524_288
    def initialize(program:, path:, seed: nil)
      @program, @path, @seed = program, path, seed
    end

    def read
      path=LocalFilesystem.native(@program.data_path(@path))
      return nil unless safe_file!(path)
      lock_path=path+'.lock'
      safe_file!(lock_path)
      File.open(lock_path,File::RDWR|File::CREAT,0o600) do |lock|
        raise IOError,'Notification journal lock unavailable' unless lock.flock(File::LOCK_SH)
        begin
          stat=safe_file!(path)
          return nil unless stat
          raise ProposalNotice::Unavailable,'Notification journal is too large' if stat.size>MAX_BYTES
          read_strict(path)
        ensure
          lock.flock(File::LOCK_UN)
        end
      end
    end

    def update(&edit)
      path = LocalFilesystem.native(@program.data_path(@path))
      lock_path = path + '.lock'
      safe_file!(lock_path)
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        raise IOError, 'Notification journal lock unavailable' unless lock.flock(File::LOCK_EX)
        begin
          safe_file!(lock_path)
          @program.update_json(@path, default: {'version'=>1, 'operations'=>{}}) do |state|
            stat = safe_file!(path)
            if stat
              raise ProposalNotice::Unavailable, 'Notification journal is too large' if stat.size > MAX_BYTES
              strict = read_strict(path)
              raise ProposalNotice::Unavailable, 'Notification journal is corrupt' unless strict.is_a?(Hash) && state.is_a?(Hash)
              state.replace(strict)
            end
            if @seed
              unless state.is_a?(Hash) && state['operations'].is_a?(Hash)
                raise ProposalNotice::Unavailable,'Notification journal is corrupt'
              end
              @seed.each { |key,entry| state['operations'][key] ||= Publication::Data.copy(entry) }
            end
            edit.call(state)
            raise ProposalNotice::Unavailable, 'Notification journal is too large' if JSON.generate(state).bytesize > MAX_BYTES
          end
        ensure
          lock.flock(File::LOCK_UN)
        end
      end
    end

    private

    def read_strict(path)
      StrictJson.parse(File.binread(path), max_nesting: 12)
    rescue JSON::ParserError
      raise ProposalNotice::Unavailable, 'Notification journal is corrupt'
    end

    def safe_file!(path)
      stat = File.lstat(path)
      raise ProposalNotice::Unavailable, 'Unsafe notification journal path' if stat.symlink? || !stat.file? || stat.nlink > 1
      stat
    rescue Errno::ENOENT
      nil
    end
  end
end
