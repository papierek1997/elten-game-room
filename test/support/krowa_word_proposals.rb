require_relative 'krowa'
require_relative 'assertions'
require_relative '../../lib/krowa_word_proposals' unless defined?(GameRoomGames::KrowaWordProposals)

module KrowaProposalFixture
  Group = Struct.new(:role)
  Forum = Struct.new(:group, :closed)
  ThreadRow = Struct.new(:id, :forum, :closed)
  Structure = Struct.new(:threads)
  Post = Struct.new(:post_id, :thread_id, :text)
  Page = Struct.new(:posts, :more, :next_before)

  class Client
    attr_accessor :role, :closed, :failure, :page, :after_call
    attr_reader :calls, :posts
    def initialize
      @role, @closed, @calls, @posts = 2, false, [], []
    end

    def api_data(method, path, params = nil, **options)
      @calls << [method, path, params, options, Thread.current]
      result = case path
      when 'structure'
        Structure.new([ThreadRow.new(28_245, Forum.new(Group.new(role), closed), false)])
      when 'posts'
        page || Page.new(posts.reverse, false, nil)
      when 'create'
        raise IOError, 'Before posting' if failure == :before
        @posts << Post.new(posts.length + 1, params[:thread_id], params[:text])
        raise IOError, 'Lost acknowledgement' if failure == :after
        posts.last.post_id
      end
      after_call&.call(path)
      result
    end
  end

  class Api
    def self.structure(client); client.api_data('GET', 'structure'); end
    def self.user_posts(client, **options); client.api_data('GET', 'posts', options); end
    def self.create_post(client, **options); client.api_data('POST', 'create', options); end
  end

  def self.service(program: KrowaTestProgram.new, client: Client.new, current_user: -> { 'Alice' })
    GameRoomGames::KrowaWordProposals.new(program, user: 'Alice', current_user: current_user,
      bank: KrowaTestGame.new.bank, forum: Api, client: client)
  end
end
