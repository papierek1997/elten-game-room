# frozen_string_literal: true

require_relative '../game_room_ui'
require_relative 'model'

module GameRoomQuizContributions
  class Views
    using GameRoomLocalization::Translations

    def initialize(program)
      @program = program
    end

    def text(value)
      GameRoomContent.utf8(value)
    end

    def choose(title, labels, index: 0)
      action, index = selection(title, labels, index: index, flags: ListBox::Flags::AnyDir)
      action == :open ? index : nil
    end

    def confirm(message)
      choose(message, [_('No'), _('Yes')]) == 1
    end

    def choose_pack(packs)
      return nil if packs.empty?
      languages = packs.map(&:language_id).uniq
      primary = GameRoomLocalization.primary_language
      language_index = languages.index { |id| id.split('-').first == primary } ||
        languages.index { |id| id.split('-').first == 'en' } || 0
      language_labels = languages.map { |id| GameRoomContent.registry.language(id)&.label || id }
      loop do
        language_index = choose(_('Language'), language_labels, index: language_index)
        return nil unless language_index
        selected = packs.select { |pack| pack.language_id == languages[language_index] }
        pack_index = choose(_('Question set'), selected.map(&:title))
        return selected[pack_index] if pack_index
      end
    end

    def library(rows, index: 0)
      actions = [[:new, _('New set'), 'n']]
      actions << [:delete, _('Delete draft'), :del] unless rows.empty?
      actions << [:refresh, _('Refresh'), 'r']
      selection(_('Create your own quiz question sets'), rows.map { |row| draft_label(row) },
        index: index, empty: _('Press Ctrl+N to create a new set or add questions to an existing one.'), actions: actions)
    end

    def set_menu(draft, index: 0)
      labels = [_('Add a question'), _('Browse questions'), _('Add a category'), _('Delete draft'), _('Send to the author')]
      actions = draft['kind'] == 'set' ? [[:details, _('Set details'), nil]] : []
      title = Model.title(draft).to_s
      selection(title.empty? ? _('Untitled set') : title, labels, index: index, actions: actions)
    end

    def questions(draft, index: 0)
      labels = draft['items'].each_with_index.map do |q, i|
        text(_('%{number}. %{question}')) % {number: i + 1, question: q['prompt'].empty? ? text(_('Untitled question')) : q['prompt']}
      end
      actions = [[:new, _('Add a question'), 'n']]
      actions << [:delete, _('Remove question'), :del] unless labels.empty?
      selection(_('Browse questions'), labels, index: index,
        empty: _('Press Ctrl+N to add a question.'), actions: actions)
    end

    def edit_question(draft, index:, remove: index < draft['items'].size, &create_category)
      value = Model.correct_first(index < draft['items'].size ? draft['items'][index] : Model.new_question(draft['categories'].first.to_s))
      fields = [edit_box(_('Question'), value['prompt'])]
      [_('Correct answer (A)'), _('Answer B'), _('Answer C'), _('Answer D')].each_with_index do |label, i|
        fields << edit_box(label, value['choices'][i])
      end
      categories = Model.categories(draft)
      selected_category = categories.include?(value['category']) ? value['category'] : categories.first.to_s
      category_labels = -> { categories.map { |s| text(s) } + [text(_('Add a new category'))] }
      category = ListBox.new(category_labels.call, header: text(_('Category')),
        index: categories.index(selected_category) || 0, quiet: true)
      category.on(:move) { selected_category = categories[category.index] if category.index < categories.size }
      category.on(:select) do
        next unless category.index == categories.size
        name = create_category&.call
        if name
          categories << name unless categories.include?(name)
          category.options = category_labels.call
          selected_category = name
        end
        category.index = categories.index(selected_category) || 0
        category.focus
      end
      fields << category
      fields << edit_box(_('Source (optional)'), value['source'])
      fields << edit_box(_('Editorial note (optional)'), value['note'])
      action = edit_form(fields, remove: remove)
      selected_category = categories[category.index] if category.index < categories.size
      updated = {'prompt' => fields[0].text, 'choices' => fields[1, 4].map(&:text),
        'correct_index' => 0, 'category' => selected_category,
        'source' => fields[6].text, 'note' => fields[7].text}
      [action, updated]
    end

    def edit_details(draft)
      specs = [['title', _('Set title')], ['language', _('Language code (for example pl or en)')],
        ['description', _('Description (optional)')]]
      fields = specs.map { |key, label| edit_box(label, draft[key]) }
      return nil unless edit_form(fields) == :save
      updated = Model.copy(draft)
      specs.each_with_index { |(key, _), i| updated[key] = fields[i].text }
      updated
    end

    def new_category
      field = edit_box(_('Category name'), '')
      edit_form([field]) == :save ? field.text : nil
    end

    # A read-only dialog is not interrupted by the next editor's focus.
    def notice(message, title: _('Question creator'))
      field = GameRoomUI::HelpText.new(text(title), type: EditBox::Flags::MultiLine | EditBox::Flags::ReadOnly,
        text: text(message), quiet: true)
      close = Button.new(text(_('Close')))
      form = GameRoomUI::Form.new([field, close], program: @program, quiet: true)
      form.accept_button = form.cancel_button = close
      form.hide(close)
      close.on(:press) { form.resume }
      form.wait
    end

    def draft_label(draft)
      return "#{text(_('The saved draft is damaged.'))} (#{draft['resource_id']})" if draft['damaged']
      title = draft.key?('items') ? Model.title(draft) : draft['title']
      count = draft.key?('items') ? draft['items'].size : draft['count']
      label = text(_('%{title}; questions: %{count}')) % {title: title.to_s.empty? ? text(_('Untitled set')) : title, count: count}
      label += '; ' + text(_('Unsaved changes on this computer')) if draft.key?('items')
      label
    end

    private

    def selection(title, labels, index: 0, empty: nil, actions: [], flags: 0)
      rows = labels.empty? ? [empty || _('No items.')] : labels
      list = ListBox.new(rows.map { |label| text(label) }, header: text(title), index: index.clamp(0, rows.size - 1),
        flags: flags, quiet: true)
      accept = Button.new(text(_('Open')))
      cancel = Button.new(text(_('Cancel')))
      form = GameRoomUI::Form.new([list, accept, cancel], program: @program, quiet: true)
      form.accept_button, form.cancel_button = accept, cancel
      form.hide(accept)
      form.hide(cancel)
      result = :back
      finish = ->(action) { result = action; form.resume }
      accept.on(:press) { finish.call(:open) unless labels.empty? }
      cancel.on(:press) { form.resume }
      list.bind_context do |menu|
        actions.each { |action, label, key| menu.option(text(label), nil, key || '') { finish.call(action) } }
      end unless actions.empty?
      GameRoomContextHelp.replace([list], actions.filter_map do |_, label, key|
        GameRoomContextHelp.shortcut_tip(key == :del ? 'Delete' : "Ctrl+#{key.upcase}", text(label)) if key
      end)
      form.wait
      [result, list.index.to_i]
    end

    def edit_form(fields, remove: false)
      save = Button.new(text(_('Save')))
      cancel = Button.new(text(_('Cancel')))
      form = GameRoomUI::Form.new([*fields, save, cancel], program: @program, quiet: true)
      form.cancel_button = cancel
      form.hide(cancel)
      result = :back
      save.on(:press) { result = :save; form.resume }
      cancel.on(:press) { form.resume }
      form.bind_context { |menu| menu.option(text(_('Remove question'))) { result = :remove; form.resume } } if remove
      form.wait
      result
    end

    def edit_box(label, value)
      EditBox.new(text(label), type: EditBox::Flags::MultiLine, text: text(value.to_s), quiet: true)
    end
  end
end
