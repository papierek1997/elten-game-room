# encoding: UTF-8
require 'json'
require 'digest'
require_relative '../../../content/languages'
require_relative '../../../content/quiz_pl_wikidata'

def assert(value, message); raise message unless value; end

pack = GameRoomContent.registry.pack('quiz.wikidata.pl')
questions = pack.data.fetch('questions')
indexed = questions.to_h { |q| [q.fetch('id'), q] }
# Individually reviewed prompts from the three October 31 reports.
# Initialisms are spaced only in these questions, never by a global rewrite
# of answer keys, word-like acronyms, chemical symbols or proper names.
expected = {
  "1z10_baa231999d19d1e6" => "Sintra, miasto słynące z architektury, leży w pobliżu której europejskiej stolicy?",
  "polqa_01942" => "Co oznaczał skrót C K w nazwie Austro-Węgier?",
  "1z10_9deac4c34e487f83" => "Co oznacza skrót K P N w nazwie partii politycznej?",
  "polqa_02149" => "Z którego języka pochodzi skrót L T D oznaczający spółkę z ograniczoną odpowiedzialnością?",
  "polqa_06469" => "Co oznacza angielski skrót D W T?",
  "1z10_72eed55f10d83473" => "Proszę rozwinąć skrót E E G.",
  "1z10_05981aabe6bba31a" => "Proszę rozwinąć skrót U S G.",
  "1z10_eade56ca7a4d504b" => "Proszę rozwinąć skrót E K G.",
  "polqa_05525" => "Jak nazywa się hormon oznaczany skrótem L T H?",
  "polqa_03787" => "Który zakon kryje się pod skrótem S J?",
  "polqa_04981" => "Która dyscyplina sportowa jest oznaczana skrótem M T B?",
  "1z10_7f22dd028a61b2f3" => "Co oznacza skrót P Z P N?",
  "1z10_8dc25587eff4d02a" => "Proszę rozszyfrować skrót W K K W używany w zawodach jeździeckich.",
  "polqa_00300" => "Co oznacza skrót K B W E?",
  "polqa_00397" => "Rozwiń skrót N F Z.",
  "polqa_00939" => "Co oznacza skrót P T T K?",
  "polqa_01141" => "Proszę rozwinąć skrót I P N.",
  "polqa_02114" => "Rozwiń skrót „C B Ś”.",
  "polqa_03834" => "Jakiej organizacji odpowiada skrót W H O?",
  "polqa_04725" => "Skrótem nazwy której organizacji międzynarodowej jest O B W E?",
  "1z10_7eabc8fb73903d3b" => "Co oznacza skrót P W P W?",
  "1z10_63526ea598725c4a" => "Którą walutę oznacza się skrótem G B P?",
  "1z10_6978cd7c468d65e3" => "Co oznacza skrót R P P w nazwie organu Narodowego Banku Polskiego?",
  "1z10_b7c47e6c48545529" => "Rozwiń polski skrót B H P.",
  "1z10_b695136b8ae8a95c" => "W nazwie P K N Orlen, co oznacza skrót P K N?",
  "1z10_d49b93e1cf7f59de" => "Rozwiń skrót nazwy instytucji państwowej I M G W.",
  "1z10_957380b825bc71ee" => "Co oznacza skrót G D D K i A?",
  "1z10_573a2357d622396d" => "Rozwiń skrót nazwy lubelskiej uczelni U M C S.",
  "1z10_e6b15b111e6c7c4a" => "W którym państwie związek publicznych nadawców radiowo-telewizyjnych posługuje się skrótem A R D?",
  "polqa_03461" => "Co oznacza skrót C M K?",
  "1z10_35b96b9f488917e0" => "Co oznacza skrót D D M?",
  "1z10_507aba3370740689" => "Ile na ile pól ma plansza do gry w Scrabble?",
  "1z10_e6c1f3c312074d5e" => "Proszę rozwinąć polski skrót A G D."
}
# Later approved batches must not invalidate the original wording audit.
# Keep its exact protected prefix and original hashes, not refreshed hashes.
prior = questions.take_while { |q| q.fetch('id') != 'community_zz_20261031b_01' }
assert(expected.length == 33 && prior.length == 14926 && indexed.length == questions.length,
  'Wrong editorial scope or duplicate question IDs')
expected.each do |id, prompt|
  assert(indexed.fetch(id).fetch('prompt') == prompt, "#{id}: approved report wording changed")
end

# Guard the entire pre-edit set, not only the three reported answer keys.
# These hashes were taken from the v19 baseline before the prompt-only edits.
non_prompt = prior.map { |q| q.except('prompt') }
assert(Digest::SHA256.hexdigest(JSON.generate(non_prompt)) ==
  '22a2475b1a15937a3792557cfda3d6c321e579f9ca4140f193a0e89be7f9520a',
  'IDs, order, categories, answers or provenance changed during the wording review')
untouched = prior.reject { |q| expected.key?(q.fetch('id')) }.map { |q| q.values_at('id', 'prompt') }
assert(Digest::SHA256.hexdigest(JSON.generate(untouched)) ==
  '3143fa3062a2de1d5a199430bdc5698e0803329be1d87786bd04fedc3dbaffbe',
  'An unrelated prompt was changed')

{
  '1z10_507aba3370740689' => ['15 na 15', ['8 na 8', '10 na 10', '19 na 19']],
  '1z10_baa231999d19d1e6' => ['Lizbony', ['Madrytu', 'Rzymu', 'Paryża']],
  'polqa_00300' => ['Konferencja Bezpieczeństwa i Współpracy w Europie',
    ['Komitet Bezpieczeństwa Wspólnot Europejskich', 'Konwencja Bezpieczeństwa Wewnętrznego Europy',
      'Komisja Bezpieczeństwa i Współpracy Ekonomicznej']]
}.each do |id, choices|
  assert(indexed.fetch(id).values_at('correct', 'wrong') == choices, "#{id}: reported question's choices changed")
end
%w[NASA PESEL RODO CEPiK].each do |word|
  assert(questions.any? { |q| q.fetch('prompt').include?(word) }, "#{word}: ordinary acronym was split")
end
puts 'Quiz reported wording 2026-10-31: 33 approved prompts; all answer keys, unrelated prompts and metadata preserved: OK'
