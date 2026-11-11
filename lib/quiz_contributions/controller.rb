# frozen_string_literal: true

require_relative 'drafts'
require_relative 'delivery'
require_relative 'views'

module GameRoomQuizContributions
  class Controller
    using GameRoomLocalization::Translations

    def initialize(program, repository: nil, drafts: nil, views: nil, delivery: nil)
      @program = program
      user = Session.name.to_s.dup
      current = -> { Session.name }
      @drafts = drafts || Drafts.new(program, user: user, current_user: current)
      @repository = repository || Repository.new(app_uuid: program.class.server_app_uuid, user: user, current_user: current)
      @delivery = delivery || Delivery.new(@repository)
      @views = views || Views.new(program)
      @unsaved = {}
    end

    def creator
      index = 0
      loop do
        local = task(_('Loading question drafts')) { @drafts.list }
        return unless local || !@unsaved.empty?
        local = @unsaved.values + local.to_a.reject { |draft| @unsaved.key?(Drafts.branch_key(draft)) }
        cloud = task(_('Loading saved drafts')) { |token| @repository.list(token: token) }
        rows = local + cloud.to_a.reject do |ref|
          local.any? { |draft| draft['resource_id'] == ref['resource_id'] ||
            ref['resource_name'] == "#{Repository::PREFIX}#{draft['id']}-#{draft['snapshot']}.json.deflate" }
        end
        action, index = @views.library(rows, index: index)
        case action
        when :back
          next if !@unsaved.empty? && !@views.confirm(_('Some changes could not be saved on this computer. Discard them and close?'))
          return
        when :new
          create
        when :open
          ref = rows.fetch(index)
          value = ref.key?('items') ? Model.copy(ref) : task(_('Loading draft')) { |token| @repository.read(ref, token: token) }
          edit(value) if value
        when :delete
          delete_draft(rows.fetch(index))
        end
      end
    end

    def edit(draft)
      index = 0
      loop do
        action, index = @views.set_menu(draft, index: index)
        case action
        when :back
          return
        when :details
          updated = details(draft)
          draft = persist(updated) if updated
        when :open
          case index
          when 0
            draft = add_question(draft)
          when 1
            draft = browse_questions(draft)
          when 2
            draft = add_category(draft)
          when 3
            return if delete_draft(draft)
          when 4
            return if submit(draft)
          end
        end
      end
    end

    private

    def browse_questions(draft)
      index = 0
      loop do
        action, index = @views.questions(draft, index: index)
        return draft if action == :back
        draft = edit_question(draft, index) if action == :open
        draft = remove_question(draft, index) if action == :delete
        if action == :new
          index = draft['items'].size
          draft = add_question(draft)
        end
      end
    end

    def add_question(draft)
      if draft['items'].size >= Model::MAX_ITEMS
        @views.notice(_('Split this set into smaller submissions (up to 1000 questions).'))
        return draft
      end
      if Model.categories(draft).empty?
        @views.notice(_('You need to add at least one category before adding questions.'))
        return draft
      end
      edit_question(draft, draft['items'].size)
    end

    def delete_draft(draft)
      return false unless @views.confirm(_('Delete this draft?'))
      task(_('Deleting draft')) do |token|
        @repository.delete(draft, token: token)
        unless draft['damaged']
          @drafts.remove(draft)
          forget_unsaved(draft)
        end
        true
      end
    end

    def create
      type = @views.choose(_('New set'), [_('Create a new set'), _('Add questions to an existing set')])
      return if type.nil?
      if type == 0
        value = Model.new_draft('set')
        value['language'] = GameRoomLocalization.primary_language.to_s
        value = details(value)
      else
        packs = GameRoomContent.registry.packs_for(game_id: 'quiz', kind: 'quiz')
        pack = @views.choose_pack(packs)
        return unless pack
        value = Model.new_draft('question', target: Model.pack_target(pack))
        categories = task(_('Loading question categories')) { pack.data.fetch('questions').map { |q| q['category'] }.uniq }
        return unless categories
        value['categories'] = categories
      end
      persist(value) if value
    end

    def details(value)
      loop do
        value = @views.edit_details(value)
        return nil unless value
        clean = task(_('Checking set details'), quiet: true) do
          data = Model.draft(value)
          errors = []
          errors << _('Set: enter a title.') if data['title'].empty?
          errors << _('Set: enter a language code, for example pl or en.') unless GameRoomContent::LANGUAGE_ID_PATTERN.match?(data['language'])
          raise Invalid, errors.map { |s| GameRoomContent.utf8(s) }.join("\r\n") unless errors.empty?
          value
        end
        return clean if clean
      end
    end

    def add_category(draft)
      name = category_name
      return draft unless name
      save_category(draft, name)
    end

    def category_name
      loop do
        value = @views.new_category
        return nil if value.nil?
        name = task(_('Checking category'), quiet: true) { Model.text!(value, 120) }
        return name if name
      end
    end

    def save_category(draft, name)
      value = Model.copy(draft)
      value['categories'] = (Model.categories(value) + [name]).uniq
      persist(value)
    end

    def edit_question(draft, index)
      existing = index < draft['items'].size
      original = Model.correct_first(draft['items'][index] || Model.new_question(Model.categories(draft).first.to_s))
      working = Model.copy(draft)
      working['items'][index] = Model.copy(original)
      loop do
        action, question = @views.edit_question(working, index: index, remove: existing) do
          name = category_name
          draft = save_category(draft, name) if name
          name
        end
        if action == :back
          return draft if question == original
          choice = @views.choose(_('Keep changes to this question?'), [_('Save'), _('Continue editing'), _('Discard unsaved changes')])
          return draft if choice == 2
          action = choice == 0 ? :save : :continue
        end
        return remove_question(draft, index) if action == :remove
        # A category added from the editor may have a newer server snapshot.
        # Keep that reference and all typed fields when saving the question.
        working = Model.copy(draft)
        working['items'][index] = question if question
        next unless action == :save
        valid = task(_('Checking question'), quiet: true) { Model.question(question, complete: false); true }
        next unless valid
        return persist(working)
      end
    end

    def persist(value)
      @unsaved[Drafts.branch_key(value)] = Model.copy(value)
      staged = task(_('Saving draft on this computer'), quiet: true) { @drafts.save(value) }
      return value unless staged
      forget_unsaved(value)
      saved = task(_('Saving draft on your account'),
        failure: _('The draft is saved only on this computer. You can keep editing or try saving it on your account again.')) do |token|
        result = @repository.save(staged, token: token)
        @drafts.remove(staged)
        result
      end
      saved || staged
    end

    def submit(draft)
      packet = task(_('Checking questions'), quiet: true) { Model.packet(draft, author: @repository.user) }
      return false unless packet
      return false unless @views.confirm(_('Send these questions to papierek? They will be reviewed before being added to the game.'))
      result = task(_('Sending question proposal')) do |token|
        key = packet['submission_id']
        unless @drafts.delivered?(key) || @repository.delivered?(key, token: token)
          @delivery.send(packet, token: token)
        end
        @drafts.delivered(key)
        true
      end
      return false unless result
      # Keep shared evidence BEFORE deleting the sender's message or draft.
      # A cleanup failure never causes another submission on an explicit retry.
      cleaned = task(_('Removing the sent draft'),
        failure: _('The questions were sent, but cleanup could not be completed. Your draft is still listed. Sending it again will retry cleanup without sending another copy.')) do |token|
        @repository.record_delivery(packet['submission_id'], token: token)
        @delivery.remove_sender_copy(packet, token: token)
        @repository.delete(draft, token: token)
        @drafts.remove(draft)
        forget_unsaved(draft)
        true
      end
      @views.notice(_('Sent to the author.')) if cleaned
      true
    end

    def forget_unsaved(value)
      key = Drafts.branch_key(value)
      @unsaved.delete(key) if @unsaved[key] && Drafts.same_version?(@unsaved[key], value)
    end

    def remove_question(draft, index)
      return draft unless index.between?(0, draft['items'].size - 1)
      return draft unless @views.confirm(_('Remove this question from the draft?'))

      value = Model.copy(draft)
      value['items'].delete_at(index)
      persist(value)
    end

    def task(title, quiet: false, failure: nil)
      EltenAPI::Tasks.run(title: GameRoomContent.utf8(title), ui: quiet ? :none : :automatic,
        cancellable: !quiet, show_after: 0.5) { |_progress, token| yield token }
    rescue EltenAPI::Tasks::Cancelled
      nil
    rescue EltenAPI::Tasks::TimedOut, EltenLink::Error, IOError, SystemCallError
      @views.notice(failure || _('The operation could not be confirmed. Your draft has been kept; try again later.'))
      nil
    rescue Error => error
      @views.notice(failure || error.message)
      nil
    end
  end
end
