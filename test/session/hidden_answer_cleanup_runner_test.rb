require_relative '../support/session_runner'
require_relative '../support/hidden_submission_files'
require_relative '../../games/scientific_war'
require_relative '../support/quiz_party_review_regressions'

def cleanup_test_clock
  GameRoomSessionClock.new(sample: -> { $quiz_regression_now },
    elapsed: -> { $quiz_regression_now.to_f }, wall: -> { $quiz_regression_now })
end

class AnswerCleanupRunnerFixture
  attr_reader :h, :game, :vaults, :runners

  def initialize(directory, game, users, options = {})
    @game = game
    @h = NativeRoomHarness.new(game: game, users: users, options: game.default_options.merge(options))
    h.start
    @vaults = users.to_h do |user|
      [user, HiddenSubmissions::Vault.new(HiddenSubmissionFiles.new(File.join(directory, user)).storage)]
    end
    @runners = users.to_h do |user|
      runner = runner_for(h, user)
      runner.instance_variable_set(:@clock, cleanup_test_clock)
      runner.instance_variable_get(:@context_template).hidden_submissions = vaults.fetch(user)
      [user, runner]
    end
  end

  def replay(user = h.users.first); h.replay(user); end
  def tick(user = h.users.first); step(h, runners.fetch(user), user); end
  def context(user)
    GameRoomGames::ActionContext.new(session_id: h.session['__id'], table_id: h.table['__id'],
      now: Time.now.to_i, hidden_submissions: vaults.fetch(user), random_source: GameRoomRandom::SeededSource.new(41))
  end
  def submit(user, action)
    h.as(user) do
      current = h.repositories.fetch(user).snapshot_for(h.session)
      status, = runners.fetch(user).submit(session: current.session, replay: replay(user), selection: action, actor: user)
      assert(status == :ok, "#{game.id} #{user}: #{status}")
    end
  end
  def stored(user, round)
    vaults.fetch(user).reveal(session_id: h.session['__id'], round_id: round, user: user)
  end
  def close; runners.each_value(&:close); end
end

Dir.mktmpdir('categories-runner-cleanup-') do |directory|
  f = AnswerCleanupRunnerFixture.new(directory, GameRoomGames::Categories.new, %w[Alice Bob Carol],
    'category_set' => 'custom', 'custom_categories' => ['country'], 'round_category_count' => 1,
    'target_score' => 100, 'round_time' => 0)
  begin
    f.tick
    round = f.game.send(:round_id, f.replay.state)
    %w[Bob Carol].each do |user|
      f.submit(user, {'kind' => 'answer_sheet', 'action' => 'submit', 'answers' => {'country' => "#{user} answer"}})
    end
    f.tick
    assert(f.replay.state[:phase] == :revealing, 'Categories did not close answering')
    action = f.game.automatic_action(f.replay('Bob'), 'Bob', context: f.context('Bob'))
    status, plan = f.game.action_for(action, f.replay('Bob'), 'Bob', context: f.context('Bob'))
    assert(status == :ok, 'Categories did not prepare a reveal')
    f.h.write('Bob', plan.events.take(1))
    partial = f.replay('Bob')
    assert(!partial.state[:reveals].key?('Bob'), 'Partial reveal unexpectedly became complete')
    f.game.cleanup_session_answers(partial, session_id: f.h.session['__id'], actors: ['Bob'], hidden_submissions: f.vaults['Bob'])
    assert(f.stored('Bob', round), 'A nonce-only receipt erased an answer')
    f.h.write('Bob', plan.events.drop(1))
    f.tick('Bob')
    assert(!f.stored('Bob', round), 'The guest worker retained its confirmed answer')
    assert(f.stored('Carol', round), 'Another account lost an unrevealed answer')
    f.tick('Carol')
    f.tick('Carol')
    f.tick
    assert(f.replay.state[:phase] == :review, 'Cleanup stopped review')
    decisions = f.game.send(:review_items, f.replay.state).to_h { |item| [item[:id], 'unique'] }
    f.submit('Alice', {'kind' => 'review', 'action' => 'finish', 'decisions' => decisions})
    f.tick
    %w[Bob Carol].each { |user| f.tick(user); assert(!f.stored(user, round), 'Scoring retained a private answer') }
    assert(f.replay.state[:scores].values_at('Bob', 'Carol') == [2, 2], 'Cleanup changed scores')
    before = f.h.events('Alice')
    $quiz_regression_now += 4
    f.tick
    assert(f.replay.state[:round] == 1 && f.h.events('Alice') == before,
      'Cleanup bypassed the five-second round break')
    $quiz_regression_now += 1
    f.tick
    assert(f.replay.state[:round] == 2, 'Cleanup prevented the next round')
    f.h.assert_converged('Categories cleanup and next round')
  ensure
    f.close
  end
end

Dir.mktmpdir('quiz-runner-cleanup-') do |directory|
  $quiz_regression_now = 1000
  quiz = QuizReviewFixture.new(%w[Alice Bob])
  stores = quiz.h.users.to_h do |user|
    [user, HiddenSubmissionFiles.new(File.join(directory, user))]
  end
  runners = quiz.h.users.to_h do |user|
    vault = HiddenSubmissions::Vault.new(stores.fetch(user).storage)
    quiz.contexts.fetch(user).hidden_submissions = vault
    runner = runner_for(quiz.h, user)
    runner.instance_variable_set(:@clock, cleanup_test_clock)
    runner.instance_variable_get(:@context_template).hidden_submissions = vault
    [user, runner]
  end
  begin
    round = quiz.game.send(:question_key, quiz.h.replay('Alice').state)
    quiz.h.users.each { |user| quiz.h.write(user, quiz.plan(user).events) }
    quiz.auto('Alice')
    quiz.h.users.each { |user| quiz.auto(user) }
    quiz.h.users.each { |user| step(quiz.h, runners.fetch(user), user) }
    quiz.h.users.each do |user|
      cold = HiddenSubmissions::Vault.new(HiddenSubmissionFiles.new(stores.fetch(user).directory).storage)
      assert(cold.reveal(session_id: quiz.h.session['__id'], round_id: round, user: user).nil?, 'Quiz worker retained confirmed answer')
    end
    quiz.advance(1004)
    step(quiz.h, runners['Alice'], 'Alice')
    assert(quiz.h.replay('Alice').state[:position] == 2, 'Quiz cleanup stalled the next question')
    quiz.h.assert_converged('Quiz cleanup')
  ensure
    runners.each_value(&:close)
  end
end

Dir.mktmpdir('scientific-war-runner-cleanup-') do |directory|
  f = AnswerCleanupRunnerFixture.new(directory, GameRoomGames::ScientificWar.new, %w[Alice Bob])
  begin
    round = f.game.send(:round_id, f.replay.state)
    f.h.users.each do |user|
      action = f.game.legal_actions(f.replay(user), user).find { |item| item['action'] == 'select' }
      f.submit(user, action)
    end
    f.h.users.each { |user| f.tick(user) }
    f.h.users.each { |user| f.tick(user) }
    assert(f.replay.state[:trick] == 2, 'Scientific War did not resolve its trick')
    f.h.users.each { |user| assert(!f.stored(user, round), 'Scientific War retained a completed choice') }
    f.h.assert_converged('Scientific War cleanup')
  ensure
    f.close
  end
end

puts 'PASS real session worker cleanup: Categories partial/complete reveal and next round, Quiz next question, Scientific War next trick, private files and cold readers'
