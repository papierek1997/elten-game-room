require_relative '../support/room_interface'
require_relative '../support/quiz_contributions'

Q = GameRoomQuizContributions
include QuestionContributionTest

class QuestionDeleteViews
  attr_accessor :confirmations, :accept
  attr_reader :seen
  def initialize; @accept = true; @confirmations = 0; @seen = []; end
  def questions(draft, index:)
    @seen << [index, draft['items'].map { |question| question['prompt'] }]
    @seen.size == 1 ? [:delete, 1] : [:back, index]
  end
  def confirm(_message); @confirmations += 1; @accept; end
  def notice(message); raise message; end
end

Dir.mktmpdir('question-delete-') do |directory|
  storage = Storage.new(directory)
  drafts = Q::Drafts.new(storage, user: 'guest', current_user: -> { 'guest' })
  files = Files.new
  repo = Q::Repository.new(app_uuid: 'test', user: 'guest', current_user: -> { 'guest' }, client: Object.new, api: files)
  value = sample
  value['items'] = %w[First Middle Last].map { |prompt| value['items'].first.merge('prompt' => prompt) }
  staged = drafts.save(value)
  saved = repo.save(staged)
  drafts.remove(staged)
  views = QuestionDeleteViews.new
  controller = Q::Controller.new(Object.new, drafts: drafts, repository: repo, views: views, delivery: Object.new)
  controller.define_singleton_method(:task) { |_title, **_options, &job| job.call(nil) }
  result = controller.send(:browse_questions, saved)
  assert(result['items'].map { |question| question['prompt'] } == %w[First Last], 'Delete removed the wrong question')
  assert(views.confirmations == 1 && views.seen.last.first == 1, 'Delete skipped confirmation or lost adjacent selection')
  assert(repo.read(repo.list.first)['items'] == result['items'], 'Delete did not persist through the ordinary account repository')
  assert(drafts.list.empty?, 'Confirmed delete left a local recovery draft')
  views.accept = false
  assert(controller.send(:remove_question, result, 0) == result, 'Cancelled delete changed the set')
  before = views.confirmations
  assert(controller.send(:remove_question, result.merge('items' => []), 0)['items'].empty? && views.confirmations == before,
    'Empty placeholder can be deleted')
end
puts 'PASS question deletion: direct list action, confirmation, exact item, next selection and ordinary draft persistence'
