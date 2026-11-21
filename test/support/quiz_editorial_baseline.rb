require 'json'

# Historical editorial checks retain their original hashes. Undo only the
# explicitly reviewed fields, after checking their current approved values;
# an unrelated edit, deletion or reordering must still fail those checks.
module QuizEditorialBaseline
  module_function

  def before_november_review(questions)
    restore(before_november_8_review(questions), 'november_review.json')
  end

  def before_november_8_review(questions)
    restore(before_november_17_review(questions), 'november_8_review.json')
  end

  def before_november_17_review(questions)
    restore(before_november_19_review(questions), 'november_17_review.json')
  end

  def before_november_19_review(questions)
    restore(questions, 'november_19_review.json')
  end

  def restore(questions, fixture_name)
    restored = questions.map(&:dup)
    indexed = restored.to_h { |question| [question.fetch('id'), question] }
    raise 'Duplicate quiz IDs' unless indexed.size == restored.size
    fixture = JSON.parse(File.read(File.expand_path("../fixtures/quiz/#{fixture_name}", __dir__), encoding: 'UTF-8'))
    # Additions are an exact approved suffix, not any row with a community ID.
    # Require the entire content and order before restoring historical hashes.
    fixture.fetch('additions', []).reverse_each do |addition|
      raise "Unapproved quiz addition: #{addition.fetch('id')}" unless restored.last == addition
      restored.pop
      indexed.delete(addition.fetch('id'))
    end
    fixture.fetch('changes').each do |change|
      if change.key?('deleted')
        row = change.fetch('deleted')
        raise "Removed question returned: #{row.fetch('id')}" if indexed.key?(row.fetch('id'))
        position = restored.index { |question| question.fetch('id') == change.fetch('before_id') }
        raise 'Missing editorial boundary' unless position
        restored.insert(position, row)
        indexed[row.fetch('id')] = row
      else
        row = indexed.fetch(change.fetch('id'))
        change.fetch('after').each do |field, value|
          raise "Unapproved quiz edit: #{row.fetch('id')}.#{field}" unless row.fetch(field) == value
        end
        row.merge!(change.fetch('before'))
      end
    end
    restored
  end
end
