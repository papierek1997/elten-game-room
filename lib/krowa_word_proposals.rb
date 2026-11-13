# encoding: UTF-8
require 'digest'
require 'json'
require_relative '../games/krowa_support/word_bank'
require_relative 'game_room_localization'

module GameRoomGames
  # A local client service, independent of moves, private solutions and chat.
  class KrowaWordProposals
    using GameRoomLocalization::Translations
    THREAD_ID = 28_245
    RULES_VERSION = 1
    MAX_SENT = 256
    MAX_PENDING = 32
    class Unavailable < StandardError; end

    class RequestClient
      def initialize(client, token, check)
        @client, @token, @check = client, token, check
      end

      def api_data(method, path, params = nil)
        @check.call(@token)
        result = @client.api_data(method, path, params, timeout: 15, cancellation_token: @token)
        @check.call(@token)
        result
      end
    end

    def initialize(program, user:, current_user: -> { Session.name }, bank: KrowaWordBank.default, forum: nil, client: nil)
      @program, @user, @current_user, @bank = program, user.to_s, current_user, bank
      @forum, @client = forum, client
      @confirmed = {}
      @path = "krowa/accounts/#{Digest::SHA256.hexdigest(@user.downcase)}/word_proposals.json"
    end

    def shortcuts
      [[[], 'current', _('Propose the word in the answer field')],
        [[:shift], 'rejected', _('Propose the last word missing from the dictionary')]].map do |modifiers, action, label|
        GameShortcut.new(key: 'b', modifiers: [:control] + modifiers, kind: :action,
          label: label, action_kind: 'krowa_word_proposal', action_name: action)
      end
    end

    def rejected(selection, status)
      return unless status == :unknown_noun && selection['kind'] == 'question' &&
        selection['question_id'].to_s.start_with?('krowa-answer-') && active?
      word = @bank.normalize(selection['answer'])
      @last_rejected = word if valid_word?(word)
    end

    def rules
      _('Only common nouns in the nominative singular or plural are accepted. Proper names, geographical names, first names, diminutives and colloquial words are not accepted. Please check the spelling before submitting. You must first be a member of the Power Games group. Your word will be posted under your Elten nickname in the word-proposal thread and will be visible to people with access to it. Submitting a word does not add it to the game. Do you understand these rules and want to send this proposal?')
    end

    def submit(which, surface:)
      check
      word = if which == 'rejected'
        @last_rejected
      else
        @bank.normalize(surface.state.dig('parts', 'answer', 'text'))
      end
      return alert(_('There is no rejected word to propose yet.')) if which == 'rejected' && word.nil?
      return alert(_('Enter one Polish word of 3 to 13 letters.')) unless valid_word?(word)
      return alert(_('This word is already in the shared dictionary.')) if @bank.include?(word)
      accepted = task { read_state['rules_version'] == RULES_VERSION }
      unless accepted
        return unless confirm_rules
        task { change_state { |state| state['rules_version'] = RULES_VERSION } }
      end
      task { |token| deliver(word, token: token) }
      alert(_('Word proposal posted: %{word}.') % {word: word})
    rescue Unavailable => error
      alert(GameRoomContent.utf8(error.message))
    rescue EltenAPI::Tasks::Cancelled, EltenAPI::Tasks::TimedOut, EltenLink::Error, IOError, SystemCallError
      alert(_('The proposal could not be confirmed. Use the shortcut again to check whether it was posted before retrying. Your answer has not been changed.'))
    end

    def deliver(word, token: nil)
      check(token)
      raise Unavailable, _('Enter one Polish word of 3 to 13 letters.') unless valid_word?(word)
      state = read_state
      return state['sent'][word] if state['sent'].key?(word)
      return remember_sent(word, @confirmed[word]) if @confirmed.key?(word)
      forum = @forum || EltenLink::Forum
      client = RequestClient.new(@client || EltenLink::Client.new, token, method(:check))
      pending = state['pending'][word]
      if pending
        existing = find_existing(forum, client, word, token)
        return remember_sent(word, existing) if existing
      end
      # Do the fresh access read after retry reconciliation, immediately
      # before preparing the write, with no further SDK reads in between.
      thread = forum.structure(client).threads.find { |item| item.id == THREAD_ID }
      # The native forum uses roles 1/2 for current members/moderators.
      unless thread && thread.forum && thread.forum.group && [1, 2].include?(thread.forum.group.role)
        raise Unavailable, _('Join the Power Games group before proposing a word. The proposal thread must be accessible to your account.')
      end
      raise Unavailable, _('The word-proposal thread is closed. Try again later.') if thread.closed || thread.forum.closed
      change_state do |stored|
        raise Unavailable, _('Too many proposals are awaiting confirmation. Retry an earlier proposal first.') if
          !stored['pending'].key?(word) && stored['pending'].length >= MAX_PENDING
        stored['pending'][word] = true
      end
      check(token)
      id = forum.create_post(client, thread_id: THREAD_ID, text: word)
      raise Unavailable, _('Posting the proposal was not confirmed. Retry to check its status.') unless id.is_a?(Integer) && id.positive?
      @confirmed[word] = id
      check(token)
      remember_sent(word, id)
    end

    private

    def confirm_rules
      text = GameRoomUI::HelpText.new(GameRoomContent.utf8(_('Word proposal rules')),
        text: GameRoomContent.utf8(rules), type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine, quiet: true)
      send_button = Button.new(GameRoomContent.utf8(_('I understand and send')))
      cancel = Button.new(GameRoomContent.utf8(_('Cancel')))
      form = GameRoomUI::Form.new([text, send_button, cancel], program: @program, quiet: true)
      form.cancel_button = cancel
      accepted = false
      send_button.on(:press) { accepted = true; form.resume }
      cancel.on(:press) { form.resume }
      form.wait
      accepted
    end

    def task(&block)
      EltenAPI::Tasks.run(title: GameRoomContent.utf8(_('Sending word proposal')), cancellable: true, show_after: 0.5) do |_progress, token|
        check(token)
        result = block.call(token)
        check(token)
        result
      end
    end

    def active?; !@user.empty? && @user.casecmp?(@current_user.call.to_s); end

    def check(token = nil)
      token&.raise_if_cancelled!
      raise Unavailable, _('The signed-in account has changed.') unless active?
    end

    def valid_word?(word)
      word.is_a?(String) && word.length.between?(3, 13) && word.match?(/\A[a-ząćęłńóśźż]+\z/u)
    end

    def validate_state(state)
      unless state.is_a?(Hash) && (state['rules_version'].nil? || state['rules_version'].is_a?(Integer)) &&
          (state['pending'].nil? || state['pending'].is_a?(Hash)) && (state['sent'].nil? || state['sent'].is_a?(Hash))
        raise Unavailable, _('The saved word-proposal settings are damaged.')
      end
      state['pending'] ||= {}
      state['sent'] ||= {}
      unless state['pending'].length <= MAX_PENDING && state['sent'].length <= MAX_SENT &&
          state['pending'].all? { |word, value| valid_word?(word) && value == true } &&
          state['sent'].all? { |word, value| valid_word?(word) && value.is_a?(Integer) && value.positive? }
        raise Unavailable, _('The saved word-proposal settings are damaged.')
      end
      state
    end

    def read_state
      check
      validate_state(@program.read_json(@path, default: {}))
    rescue JSON::ParserError
      raise Unavailable, _('The saved word-proposal settings are damaged.')
    end

    def change_state
      check
      result = nil
      written = @program.update_json(@path, default: {}) do |state|
        check
        validate_state(state)
        result = yield state
      end
      raise IOError, 'Cannot save word proposals' if written == false
      result
    rescue JSON::ParserError
      raise Unavailable, _('The saved word-proposal settings are damaged.')
    end

    def remember_sent(word, id)
      @confirmed[word] = id
      change_state do |state|
        state['pending'].delete(word)
        state['sent'][word] = id
        state['sent'].shift while state['sent'].length > MAX_SENT
      end
      @confirmed.delete(word)
      id
    end

    def find_existing(forum, client, word, token)
      before = nil
      10.times do
        page = forum.user_posts(client, user: @user, before: before, limit: 50)
        check(token)
        found = page.posts.find { |post| post.thread_id == THREAD_ID && post.text.to_s.strip == word && post.post_id.to_i.positive? }
        return found.post_id if found
        return nil if page.more == false
        cursor = page.next_before
        break unless page.more == true && cursor.is_a?(Integer) && cursor.positive? && (before.nil? || cursor < before)
        before = cursor
      end
      raise Unavailable, _('The previous proposal could not be checked completely. Check the forum before trying again.')
    end
  end
end
