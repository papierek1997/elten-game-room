require_relative '../../support/quiz_party_review_regressions'

fixture = QuizReviewFixture.new(%w[Alice Bob])
h, game = fixture.h, fixture.game
question_event = h.events('Alice').last
assert(question_event['action'] == 'question' && question_event['value'].match?(/\A1,1,q:[0-9a-f]{32}\z/),
  'New questions did not use the unbiased seed dialect')
assert(h.view('Alice').calls[:random] == 2, 'Question selection and answer order need only one shared native draw')
assert(question_event['__server_random'].dig('recipe', 'template') == '1,1,q:{seed}', 'Wrong native question proof')

initial = h.replay('Alice')
shown = game.surface_spec(initial, 'Alice').options.map(&:label)
correct = game.send(:correct_option_index, initial.state)
assert(initial.state[:answer_order_seed].match?(/\A[0-9a-f]{64}\z/), 'Answer seed missing from accepted state')
assert(game.reportable_question(initial).fetch('answers') == shown, 'Question reports use a different order')
10.times do
  h.users.each do |user|
    snapshot = h.repositories.fetch(user).snapshot_for(h.session)
    fresh_game = GameRoomGames::QuizParty.new
    replay = fresh_game.replay(snapshot.session, snapshot.events, h.repositories.fetch(user))
    assert(fresh_game.surface_spec(replay, user).options.map(&:label) == shown, 'Peers or cold refresh changed answer order')
    assert(fresh_game.send(:correct_option_index, replay.state) == correct, 'Peers disagree about the correct index')
  end
end

# An invalid incoming draw cannot replace the current answer order.
bad = question_event.merge('value'=>'1,1,q:' + 'z' * 32)
prefix = h.events('Alice')[0...-1]
refused = game.replay(h.session, prefix + [bad], h.repositories.fetch('Alice'))
assert(refused.state[:phase] == :starting && !refused.state.key?(:answer_order_seed), 'Malformed entropy was accepted')

wrong = (correct + 1) % 4
{'Alice'=>correct, 'Bob'=>wrong}.each do |user, index|
  replay = h.replay(user)
  h.submit(user, {'kind'=>'question', 'action'=>'submit',
    'question_id'=>game.send(:question_surface_id, replay.state), 'answer'=>index.to_s},
    context:fixture.contexts.fetch(user))
end
fixture.auto('Alice')
fixture.auto('Alice')
fixture.auto('Bob')
fixture.auto('Alice')
result = h.replay('Alice')
assert(result.state[:scores] == {'Alice'=>1, 'Bob'=>0}, 'Commit/reveal scored a different ordering')
h.assert_converged('Unbiased question answers scored')
fixture.advance(1004)
fixture.auto('Alice')
next_question = h.replay('Alice')
assert(next_question.state[:position] == 2 && next_question.state[:answer_order_seed] != initial.state[:answer_order_seed],
  'Next question reused the previous answer seed')
h.assert_converged('Next question has fresh answer entropy')
puts 'PASS Quiz native answer ordering: one server draw, two peers/cold refresh, reporting, malformed seed refusal, private commit/reveal, next question and scores'
