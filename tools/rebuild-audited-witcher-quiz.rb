require "digest"
require "json"
require "open3"
require_relative "quiz-pack-writer"

ROOT = File.expand_path("..", __dir__)
REMOVALS_PATH = File.join(ROOT, "content", "QUIZ_WITCHER_REMOVALS.json")
EDITS_PATH = File.join(ROOT, "content", "QUIZ_WITCHER_EDITS.json")
LEDGER_PATH = File.join(ROOT, "content", "QUIZ_WITCHER_AUDIT_LEDGER.json")
IMPORT_REPORT_PATH = File.join(ROOT, "content", "QUIZ_IMPORT_REPORT.json")
PACK_PATH = File.join(ROOT, "content", "quiz_witcher_pl.rb")
DATA_PATH = File.join(ROOT, "content", "quiz_witcher_pl_data.rb")
MEDIUM_PATH = File.join(ROOT, "content", "quiz_witcher_pl_medium_data.rb")
SOURCE_MODULE = "Pack1f9366a686ccc2dddda06ad6"
MEDIUM_MODULE = "WitcherPolishMediumData"
REQUIRED_QUESTION_KEYS = %w[id category level prompt correct wrong].freeze
OPTIONAL_QUESTION_KEYS = %w[source_links].freeze
EXPECTED_DATA_VERSION = 3
EXPECTED_WIKI_SNAPSHOT = "2026-09-14T09:39:11.882682+00:00"
EXPECTED_REPORT_SHA256 = {
  "czarodzieje" => "d66858d3eea647c0e8f2f2acea632eea0edfc8849e5d10e34ebde7b6160dd26d",
  "geografia" => "2be89984108925b2b021173b2fa0ff1199b44a205a31d8bd9d2e8771e00caa98",
  "potwory" => "209cb00d26046ed8100b32a99778541e7fb7d12ee57b2e322de77e912a29f82b",
  "wiedzmini" => "a40977b06e00b79fe44c59b41a062904dfb6236ec495ae806f168aa657f2fc6e",
  "wladcy" => "673805df4d71daf91e6ff897818468f31198bbafd0e06d440ff3000f91a02135",
  "mniej_znane_0" => "e0f544577ba5b1237b05bcbe0a7f3a72a766aa8b5d2023b9ea1b928273f9f430",
  "mniej_znane_1" => "461767fe8fa0e8d928e0017a10a91de53daa0be71f924b5eb698fbd7b4bb204b",
  "mniej_znane_2" => "3b38bfb21c7a89333be22613b4f7f3da720c7058b99d703b99af6cf7bdf002e9",
  "schemas" => "7e279026ffb7d32ee9bc9dee6338ce984e3c60bc193f880cf04f55e4d172a94f",
  "crosscut" => "cc814e367cff167b3b4390bc808c5ab6e9973df92a331346c7cb7dd1710ae8d7"
}.freeze
EXPECTED_ARTIFACT_SHA256 = {
  REMOVALS_PATH => "fc7dd6e0307ba39b10415b34c681483aead9d814202ec159ed42c52ff2e7ca66",
  EDITS_PATH => "c81076b3f7dc741be62ab31be00552211a75622108c69f8330b8a3ee4ec719c5",
  LEDGER_PATH => "9b329d39d6c2c74c582439367c651d47614915c6590720fcf67d7fd8aac85ab8",
  IMPORT_REPORT_PATH => "91917314389c1d5500778c989ac7e0bc77bf4869eec30c4766fa66e7b5cd608e"
}.freeze


def fail_unless(condition, message)
  raise message if !condition
end


def extract_payload(text)
  match = text.match(/JSON\.parse\(<<'([^']+)'\)\r?\n(.*?)\r?\n\1\r?\n/m)
  raise "quiz payload not found" if match == nil

  JSON.parse(match[2])
end


def git_text(revision, path)
  stdout, stderr, status = Open3.capture3("git", "-C", ROOT, "show", "#{revision}:#{path}")
  raise "cannot read #{path} at #{revision}: #{stderr}" if !status.success?

  stdout
end


def module_source(module_name, payload, prefix)
  json = JSON.pretty_generate(payload)
  delimiter = "#{prefix}_#{Digest::SHA256.hexdigest(json)}"
  [
    "require \"json\"",
    "module GameRoomContent",
    "  module #{module_name}",
    "    def self.load",
    "      JSON.parse(<<'#{delimiter}')",
    json,
    delimiter,
    "    end",
    "  end",
    "end",
    ""
  ].join("\n")
end


def pack_source(definitions)
  lines = ["require_relative \"../lib/game_content\"", "", "witcher_sets = ["]
  definitions.each_with_index do |definition, index|
    lines.concat([
      "  {",
      "    id: #{definition.fetch(:id).inspect},",
      "    set_id: #{definition.fetch(:set_id).inspect},",
      "    title: #{definition.fetch(:title).inspect},",
      "    scope: #{definition.fetch(:scope).inspect},",
      "    entry_count: #{definition.fetch(:entry_count)},",
      "    checksum: #{definition.fetch(:checksum).inspect}",
      "  }#{index == definitions.length - 1 ? "" : ","}"
    ])
  end
  lines.concat([
    "].freeze",
    "",
    "witcher_sets.each do |definition|",
    "  scope = definition.fetch(:scope)",
    "  GameRoomContent.registry.register_pack(GameRoomContent::Pack.new(",
    "    id: definition.fetch(:id),",
    "    set_id: definition.fetch(:set_id),",
    "    kind: :quiz,",
    "    language_id: \"pl-PL\",",
    "    version: 3,",
    "    title: definition.fetch(:title),",
    "    game_ids: [\"quiz\"],",
    "    license: \"CC BY-SA 3.0 (Fandom, Wiedźmin Wiki)\",",
    "    author: \"ELTEN Game Room\",",
    "    entry_count: definition.fetch(:entry_count),",
    "    checksum: definition.fetch(:checksum),",
    "    loader: lambda {",
    "      require_relative \"quiz_witcher_pl_sets\"",
    "      GameRoomContent::WitcherPolishSets.load(scope)",
    "    }",
    "  ))",
    "end",
    ""
  ])
  lines.join("\n")
end


def question_without_medium(question)
  question.reject { |key, _value| key == "medium_code" }
end


def valid_question_keys?(question, medium: false)
  required = REQUIRED_QUESTION_KEYS + (medium ? ["medium_code"] : [])
  keys = question.keys
  (required - keys).empty? && (keys - required - OPTIONAL_QUESTION_KEYS).empty?
end


def explicit_medium(prompt)
  text = prompt.downcase
  return "s" if text.match?(/ekranizac|serial|netflix|filmie/)
  return "g" if text.match?(/\bw grach\b|\bw grze\b|\bktórej grze\b|gwint/)
  return "b" if text.match?(/\bw książk|\bktórej książ|opowiadani|powieść/)

  nil
end

removals = JSON.parse(File.read(REMOVALS_PATH, encoding: "UTF-8"))
edits = JSON.parse(File.read(EDITS_PATH, encoding: "UTF-8"))
ledger = JSON.parse(File.read(LEDGER_PATH, encoding: "UTF-8"))
revision = edits.fetch("base_revision")
fail_unless(revision == removals.fetch("base_revision") && revision == ledger.fetch("base_revision"), "audit inputs use different base revisions")
fail_unless(revision.match?(/\A[0-9a-f]{40}\z/), "invalid base revision")
base_paths = ["content/quiz_witcher_pl_data.rb", "content/quiz_witcher_pl_medium_data.rb"]
base_texts = base_paths.to_h { |path| [path, git_text(revision, path)] }
fail_unless(base_paths.all? { |path| Digest::SHA256.hexdigest(base_texts.fetch(path)) == ledger.fetch("base_blob_sha256").fetch(path) }, "pinned base data differs from the audit ledger")
base_data = extract_payload(base_texts.fetch("content/quiz_witcher_pl_data.rb"))
base_medium = extract_payload(base_texts.fetch("content/quiz_witcher_pl_medium_data.rb"))
base_questions = base_data.fetch("questions")
base_ids = base_questions.map { |question| question.fetch("id") }
fail_unless(base_questions.length == 6_571 && base_ids.uniq.length == base_ids.length, "unexpected base Witcher question data")
fail_unless(base_medium.fetch("version") == 2, "unexpected base Witcher medium version")
fail_unless(base_medium.fetch("media").keys.sort == base_ids.sort, "base medium map does not cover the base questions")
materialized = base_questions.map do |question|
  id = question.fetch("id")
  result = {
    "id" => id,
    "category" => question.fetch("category"),
    "level" => question.fetch("level"),
    "prompt" => base_medium.fetch("prompts").fetch(id, question.fetch("prompt")),
    "correct" => question.fetch("correct"),
    "wrong" => question.fetch("wrong"),
    "medium_code" => base_medium.fetch("media").fetch(id)
  }
  result["source_links"] = question.fetch("source_links") if question.key?("source_links")
  result
end
base_by_id = materialized.to_h { |question| [question.fetch("id"), question] }
removed = removals.fetch("removals")
removed_ids = removed.map { |row| row.fetch("id") }
removed_by_id = removed.to_h { |row| [row.fetch("id"), row] }
edit_rows = edits.fetch("edits")
edit_rows_by_id = edit_rows.to_h { |row| [row.fetch("original_id"), row] }
edit_by_id = edit_rows_by_id.transform_values { |row| row.fetch("replacement") }
fail_unless(removed.length == removals.fetch("removal_count") && removed_by_id.length == removed.length, "removal manifest count is invalid")
fail_unless(edit_rows.length == edits.fetch("edit_count") && edit_rows_by_id.length == edit_rows.length, "edit manifest count is invalid")
fail_unless((removed_ids & edit_rows_by_id.keys).empty?, "a question is both removed and edited")
fail_unless((removed_ids + edit_rows_by_id.keys).all? { |id| base_by_id.key?(id) }, "audit manifest references an unknown question")
removed.each do |row|
  base = base_by_id.fetch(row.fetch("id"))
  fail_unless(row.fetch("original") == question_without_medium(base), "a removal snapshot differs from the pinned base")
  fail_unless(row.fetch("category") == base.fetch("category") && row.fetch("medium_code") == base.fetch("medium_code"), "removal metadata differs from the pinned base")
end
edit_rows.each do |row|
  id = row.fetch("original_id")
  base = base_by_id.fetch(id)
  replacement = row.fetch("replacement")
  fail_unless(row.fetch("original") == base, "an edit original differs from the pinned base")
  fail_unless(replacement.fetch("id") == id && valid_question_keys?(replacement, medium: true), "an edit has an invalid schema")
  fail_unless(replacement != base, "an edit does not change its original")
  fail_unless(replacement["source_links"] == base["source_links"], "an edit changed explicit source links") if base.key?("source_links")
  stated_medium = explicit_medium(replacement.fetch("prompt"))
  fail_unless(stated_medium == nil || stated_medium == replacement.fetch("medium_code"), "an edit contradicts its medium")
end
summary = edits.fetch("summary")
fail_unless(summary == removals.fetch("summary"), "audit manifests have different summaries")
expected_summary = {
  "base_questions" => 6_571,
  "removed" => removed.length,
  "edited" => edit_rows.length,
  "unchanged" => 6_571 - removed.length - edit_rows.length,
  "remaining" => 6_571 - removed.length
}
fail_unless(expected_summary.all? { |key, value| summary.fetch(key) == value }, "audit summary totals are invalid")
final = materialized.filter_map do |question|
  id = question.fetch("id")
  next if removed_by_id.key?(id)

  edit_by_id.fetch(id, question)
end
fail_unless(final.length == 384, "unexpected final Witcher question count")
fail_unless(final.map { |question| question.fetch("id") }.uniq.length == final.length, "final question IDs are not unique")
fail_unless(final.map { |question| [question.fetch("prompt").downcase, question.fetch("correct").downcase] }.uniq.length == final.length, "final facts contain duplicates")
fail_unless(final.all? { |question| valid_question_keys?(question, medium: true) }, "final data has an invalid question schema")
fail_unless(final.all? { |question| %w[easy medium hard].include?(question.fetch("level")) }, "final data has an invalid level")
fail_unless(final.all? { |question| %w[b g s].include?(question.fetch("medium_code")) }, "final data has an invalid medium")
fail_unless(final.all? { |question| explicit_medium(question.fetch("prompt")) == nil || explicit_medium(question.fetch("prompt")) == question.fetch("medium_code") }, "a final prompt contradicts its medium")
fail_unless(final.all? do |question|
  options = [question.fetch("correct"), *question.fetch("wrong")]
  question.fetch("wrong").length == 3 && options.all? { |value| !value.to_s.strip.empty? } && options.map(&:downcase).uniq.length == 4
end, "final data has invalid answer options")
summary_expectations = {
  "base_questions" => base_questions.length,
  "removed" => removed.length,
  "edited" => edit_rows.length,
  "unchanged" => base_questions.length - removed.length - edit_rows.length,
  "remaining" => final.length,
  "remaining_by_medium" => final.map { |question| question.fetch("medium_code") }.tally,
  "remaining_by_category" => final.map { |question| question.fetch("category") }.tally,
  "remaining_by_level" => final.map { |question| question.fetch("level") }.tally,
  "removals_by_category" => removed.map { |row| row.fetch("category") }.tally,
  "edits_by_category" => edit_rows.map { |row| base_by_id.fetch(row.fetch("original_id")).fetch("category") }.tally,
  "edit_reports" => edit_rows.map { |row| row.fetch("replacement_report") }.tally
}
summary_expectations.each do |key, value|
  fail_unless(summary.fetch(key) == value, "audit summary #{key} is invalid")
end
base_source_links = materialized.to_h { |question| [question.fetch("id"), question["source_links"]] }
fail_unless(final.all? { |question| base_source_links[question.fetch("id")] == question["source_links"] }, "final data lost explicit source links")
source = base_data.fetch("source")
runtime_questions = final.map { |question| question_without_medium(question) }
runtime_data = { "questions" => runtime_questions, "source" => source }
runtime_medium = {
  "version" => 3,
  "source_question_count" => final.length,
  "media" => final.to_h { |question| [question.fetch("id"), question.fetch("medium_code")] },
  "prompts" => {}
}
scopes = {
  all: ->(_question) { true },
  games: ->(question) { question.fetch("medium_code") == "g" },
  books_screen: ->(question) { question.fetch("medium_code") != "g" }
}
metadata = [
  { id: "quiz.witcher.pl", set_id: "quiz.witcher", title: "Wiedźmin", scope: :all },
  { id: "quiz.witcher.g.pl", set_id: "quiz.witcher.g", title: "Wiedźmin — gry", scope: :games },
  { id: "quiz.witcher.b.pl", set_id: "quiz.witcher.b", title: "Wiedźmin — książki i ekranizacje", scope: :books_screen }
]
definitions = metadata.map do |definition|
  selected = final.select(&scopes.fetch(definition.fetch(:scope))).map { |question| question_without_medium(question) }
  data = { "questions" => selected, "source" => source, "data_version" => 3 }
  pack = GameRoomContent::Pack.new(
    id: definition.fetch(:id), set_id: definition.fetch(:set_id), kind: :quiz,
    language_id: "pl-PL", version: 3, title: definition.fetch(:title), game_ids: ["quiz"],
    license: "CC BY-SA 3.0 (Fandom, Wiedźmin Wiki)", author: "ELTEN Game Room", data: data
  )
  definition.merge(entry_count: selected.length, checksum: pack.checksum)
end
calculated = definitions.to_h { |definition| [definition.fetch(:id), { "questions" => definition.fetch(:entry_count), "checksum" => definition.fetch(:checksum) }] }
fail_unless(calculated == ledger.fetch("expected_packs") && calculated == edits.fetch("expected_packs"), "final pack counts or checksums differ from the audit manifests")
fail_unless(summary.fetch("expected_packs") == calculated && summary.fetch("data_version") == EXPECTED_DATA_VERSION, "audit summary pack metadata is invalid")
fail_unless([removals, edits, ledger, summary].all? { |document| document.fetch("wiki_snapshot") == EXPECTED_WIKI_SNAPSHOT }, "audit inputs use an invalid source snapshot")
report_names = %w[czarodzieje geografia potwory wiedzmini wladcy mniej_znane_0 mniej_znane_1 mniej_znane_2 schemas crosscut]
report_manifest = ledger.fetch("report_manifest")
fail_unless(report_manifest.keys.sort == report_names.sort && report_manifest.keys.sort == EXPECTED_REPORT_SHA256.keys.sort, "audit report manifest is incomplete")
reports_root = File.join(ROOT, "content", "witcher_audit_reports")
report_documents = report_manifest.to_h do |name, entry|
  path = File.expand_path(entry.fetch("path"), ROOT)
  fail_unless(path.start_with?(reports_root + File::SEPARATOR), "audit report path escapes its directory")
  fail_unless(path == File.join(reports_root, "#{name}.json"), "audit report path is not canonical")
  fail_unless(File.file?(path), "a canonical audit report is missing")
  bytes = File.binread(path)
  digest = Digest::SHA256.hexdigest(bytes)
  fail_unless(digest == entry.fetch("sha256") && digest == EXPECTED_REPORT_SHA256.fetch(name), "a canonical audit report failed its checksum")
  document = JSON.parse(bytes)
  fail_unless(document.fetch("name") == name, "a canonical audit report has the wrong name")
  fail_unless(document.fetch("input_count") == entry.fetch("input_count"), "audit report input count is invalid")
  fail_unless(document.fetch("checked_questions") == entry.fetch("checked_questions"), "audit report checked count is invalid")
  fail_unless(document.fetch("findings_count") == entry.fetch("findings_count"), "audit report finding count is invalid")
  [name, document]
end
partition_names = report_names - %w[schemas crosscut]
partition_checks = {}
partition_findings = {}
partition_names.each do |name|
  document = report_documents.fetch(name)
  rows = document.fetch("checks")
  findings = document.fetch("findings")
  report_ids = rows.map { |row| row.fetch("id") }
  finding_ids = findings.map { |row| row.fetch("id") }
  fail_unless(rows.length == document.fetch("checked_questions") && rows.length == document.fetch("input_count") && report_ids.uniq.length == rows.length, "a partition report has invalid check coverage")
  finding_actions = findings.to_h { |finding| [finding.fetch("id"), finding.fetch("action")] }
  fail_unless(rows.all? do |row|
    if finding_actions.key?(row.fetch("id"))
      ["finding", finding_actions.fetch(row.fetch("id"))].include?(row.fetch("status"))
    else
      %w[keep pass].include?(row.fetch("status"))
    end
  end, "a partition report has an invalid status")
  fail_unless(findings.length == document.fetch("findings_count") && finding_ids.uniq.length == findings.length && (finding_ids - report_ids).empty?, "a partition report has invalid findings")
  fail_unless(findings.all? do |finding|
    %w[remove edit reverify].include?(finding.fetch("action")) &&
      !finding.fetch("reason_codes").empty? && !finding.fetch("reason").empty? &&
      finding.fetch("evidence_urls").all? { |url| url.match?(/\Ahttps?:\/\//) }
  end, "a partition finding has invalid semantics")
  rows.each do |row|
    fail_unless(!partition_checks.key?(row.fetch("id")), "partition audit reports overlap")
    partition_checks[row.fetch("id")] = row.merge("report" => name)
  end
  partition_findings[name] = findings.to_h { |row| [row.fetch("id"), row] }
end
fail_unless(partition_checks.keys.sort == base_ids.sort, "partition audit reports do not cover the base questions")
crosscut = report_documents.fetch("crosscut")
fail_unless(crosscut.fetch("checked_ids").sort == base_ids.sort && crosscut.fetch("checked_ids").uniq.length == base_ids.length, "cross-cutting audit coverage is invalid")
crosscut_finding_ids = crosscut.fetch("findings").map { |row| row.fetch("id") }
fail_unless(crosscut.fetch("input_count") == base_ids.length && crosscut.fetch("findings").length == crosscut.fetch("findings_count"), "cross-cutting audit counts are invalid")
fail_unless(crosscut_finding_ids.uniq.length == crosscut_finding_ids.length && (crosscut_finding_ids - base_ids).empty?, "cross-cutting audit findings are invalid")
fail_unless(crosscut.fetch("findings").all? do |finding|
  %w[remove edit reverify].include?(finding.fetch("action")) &&
    !finding.fetch("reason_codes").empty? && !finding.fetch("reason").empty? &&
    finding.fetch("evidence_urls").all? { |url| url.start_with?("https://") }
end, "a cross-cutting finding has invalid semantics")
partition_findings["crosscut"] = crosscut.fetch("findings").to_h { |row| [row.fetch("id"), row] }
schemas = report_documents.fetch("schemas")
fail_unless(ledger.fetch("schema_review") == schemas, "schema review differs from its canonical report")
fail_unless(schemas.fetch("schema_count") == schemas.fetch("schemas").length && schemas.fetch("input_count") == base_ids.length, "schema review counts are invalid")
schema_ids = schemas.fetch("schemas").flat_map { |row| row.fetch("affected_ids") }
fail_unless(schema_ids.length == base_ids.length && schema_ids.uniq.length == base_ids.length && schema_ids.sort == base_ids.sort, "schema review does not cover each base question once")
schema_by_id = {}
schema_key_by_id = {}
schemas.fetch("schemas").each do |schema|
  fail_unless(schema.fetch("affected_ids").length == schema.fetch("count"), "a schema review count is invalid")
  schema.fetch("affected_ids").each do |id|
    schema_by_id[id] = schema.fetch("schema")
    schema_key_by_id[id] = [schema.fetch("origin"), schema.fetch("schema")]
  end
end
checks = ledger.fetch("question_checks")
checks_by_id = checks.to_h { |row| [row.fetch("id"), row] }
fail_unless(ledger.fetch("questions_checked") == 6_571 && checks_by_id.length == 6_571, "audit ledger does not cover all base questions")
fail_unless(checks_by_id.keys.sort == base_ids.sort, "audit ledger IDs do not match the base questions")
expected_outcomes = base_ids.to_h do |id|
  outcome = removed_by_id.key?(id) ? "remove" : (edit_rows_by_id.key?(id) ? "edit" : "keep")
  [id, outcome]
end
policy_manifest = ledger.fetch("policy_manifest")
known_sources = report_manifest.keys + policy_manifest.keys
base_by_id.each do |id, base|
  row = checks_by_id.fetch(id)
  outcome = expected_outcomes.fetch(id)
  final_medium = outcome == "remove" ? nil : (outcome == "edit" ? edit_by_id.fetch(id).fetch("medium_code") : base.fetch("medium_code"))
  partition_check = partition_checks.fetch(id)
  partition_name = partition_check.fetch("report")
  decision = outcome == "remove" ? removed_by_id.fetch(id) : (outcome == "edit" ? edit_rows_by_id.fetch(id) : nil)
  expected_reports = if decision == nil
    values = [partition_name, "crosscut"]
    values << "non_dispositive_medium_scope" if partition_findings.fetch(partition_name).key?(id)
    values
  else
    decision.fetch("reports")
  end
  expected_reasons = decision == nil ? [] : decision.fetch("reason_codes")
  fail_unless(row.fetch("outcome") == outcome, "a ledger outcome differs from its manifest")
  fail_unless(row.fetch("category") == base.fetch("category"), "a ledger category differs from the base")
  fail_unless(row.fetch("schema") == schema_by_id.fetch(id), "a ledger schema differs from the canonical schema report")
  fail_unless(row.fetch("original_medium_code") == base.fetch("medium_code") && row["final_medium_code"] == final_medium, "a ledger medium differs from its decision")
  fail_unless(row.fetch("reason_codes") == expected_reasons && row.fetch("reports") == expected_reports, "a ledger rationale differs from its decision")
  fail_unless(row.fetch("reports").all? { |name| known_sources.include?(name) }, "a ledger row references an unknown audit source")
  fail_unless(
    row.fetch("source_title") == partition_check.fetch("source_title") &&
      row.fetch("source_url") == partition_check.fetch("source_url") &&
      row.fetch("source_revid") == partition_check.fetch("source_revid") &&
      row.fetch("source_timestamp") == partition_check.fetch("source_timestamp"),
    "a ledger source differs from its canonical partition report"
  )
  if decision == nil
    fail_unless(!partition_findings.fetch("crosscut").key?(id), "an unaddressed cross-cutting finding remains playable")
    if partition_findings.fetch(partition_name).key?(id)
      finding = partition_findings.fetch(partition_name).fetch(id)
      fail_unless(row.fetch("reports").include?("non_dispositive_medium_scope") && finding.fetch("reason_codes") == ["medium_scope_unsupported"], "a partition finding was retained without a narrow policy")
    end
  else
    fail_unless(!decision.fetch("reason_codes").empty? && !decision.fetch("reasons").empty?, "a manifest decision has no rationale")
    fail_unless(decision.fetch("evidence_urls").include?(row.fetch("source_url")), "a manifest decision omits its source URL")
    decision.fetch("reports").each do |name|
      next if policy_manifest.key?(name)
      finding = partition_findings.fetch(name).fetch(id) { fail_unless(false, "a manifest cites an audit report without a matching finding") }
      fail_unless((finding.fetch("reason_codes") - decision.fetch("reason_codes")).empty?, "a manifest omits canonical finding reason codes")
      fail_unless(decision.fetch("reasons").include?(finding.fetch("reason")), "a manifest omits canonical finding rationale")
      fail_unless((finding.fetch("evidence_urls") - decision.fetch("evidence_urls")).empty?, "a manifest omits canonical finding evidence")
      fail_unless(outcome == "remove" || finding.fetch("action") == "edit", "an edit is incompatible with its canonical finding action")
    end
    if outcome == "edit"
      replacement_report = decision.fetch("replacement_report")
      fail_unless(replacement_report != nil && decision.fetch("reports").include?(replacement_report), "an edit has no closed replacement report")
      fail_unless(partition_findings.fetch(replacement_report).fetch(id).fetch("action") == "edit", "an edit replacement report has an incompatible action")
    end
  end
end
fail_unless(checks.map { |row| row.fetch("outcome") }.tally == expected_outcomes.values.tally, "audit ledger outcome totals are invalid")
fail_unless(ledger.fetch("outcomes") == expected_outcomes.values.tally, "audit ledger top-level outcomes are invalid")
fail_unless(ledger.fetch("source_pages_checked") == checks.map { |row| row.fetch("source_title") }.uniq.length, "audit ledger source-page count is invalid")
fail_unless(policy_manifest.keys.sort == %w[independent_review_followup non_dispositive_medium_scope parent_schema_policy], "audit policy manifest contains an unknown policy")
policy_manifest.each do |name, policy|
  referenced = checks.count { |row| row.fetch("reports").include?(name) }
  fail_unless(policy.fetch("question_count") == referenced, "audit policy count is invalid")
end
parent_policy = policy_manifest.fetch("parent_schema_policy")
fail_unless(parent_policy.fetch("schema_statuses") == ["remove"], "parent schema policy has invalid statuses")
removed_schema_keys = schemas.fetch("schemas").select { |row| parent_policy.fetch("schema_statuses").include?(row.fetch("status")) }
  .map { |row| [row.fetch("origin"), row.fetch("schema")] }
additional_schema_keys = parent_policy.fetch("additional_schema_keys").map { |row| [row.fetch("origin"), row.fetch("schema")] }
expected_additional_schema_keys = [
  ["base_generator", "czarodziej_zamieszkanie"],
  ["mage_generator", "kto_tytul"],
  ["mage_generator", "opowiadanie"],
  ["mage_generator", "org_siedziba"],
  ["mage_generator", "rasa"],
  ["mage_generator", "relacja"],
  ["mage_generator", "tytul"],
  ["six_categories", "geo_moneta"],
  ["six_categories", "geo_polozenie"],
  ["six_categories", "geo_ustroj"],
  ["six_categories", "mon_zywienie"],
  ["six_categories", "org_siedziba"],
  ["six_categories", "os_mieszkanie"],
  ["six_categories", "os_relacja"],
  ["six_categories", "os_smierc_miejsce"],
  ["six_categories", "untraced"]
]
fail_unless(additional_schema_keys.sort == expected_additional_schema_keys, "parent schema policy has invalid exceptions")
parent_keys = (removed_schema_keys + additional_schema_keys).uniq
parent_ids = schema_key_by_id.select { |_id, key| parent_keys.include?(key) }.keys.sort
parent_references = checks.select { |row| row.fetch("reports").include?("parent_schema_policy") }.map { |row| row.fetch("id") }.sort
fail_unless(parent_ids == parent_references && parent_ids.all? { |id| expected_outcomes.fetch(id) == "remove" }, "parent schema policy coverage is invalid")
followup_codes = %w[
  audiobook_role_misworded_as_book cast_medium_mismatch invisible_unicode_format_character malformed_subpage_label
  mentioned_not_appeared
  no_op_replacement non_single_book_in_book_options non_standalone_work_in_game_options
  nonparallel_book_options prompt_medium_alignment source_supported_wrong_option
  unresolved_location_finding unresolved_option_containment untraced_no_op_finding
  singular_prompt_for_plural_subject term_misclassified_as_character uncertain_conflicting_numeric_value
  unsupported_book_scope unsupported_game_appearance unverified_location_replacement
]
followup_rows = checks.select { |row| row.fetch("reports").include?("independent_review_followup") }
fail_unless(followup_rows.all? { |row| !(row.fetch("reason_codes") & followup_codes).empty? }, "independent review policy covers an ineligible question")
fail_unless(ledger.fetch("data_version") == EXPECTED_DATA_VERSION && summary.fetch("data_version") == EXPECTED_DATA_VERSION, "audit data version is invalid")
snapshot = ledger.fetch("wiki_snapshot")
fail_unless(snapshot.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?\+00:00\z/), "audit source snapshot is invalid")
fail_unless(checks.all? do |row|
  row.fetch("source_url").start_with?("https://wiedzmin.fandom.com/wiki/") &&
    row.fetch("source_revid").is_a?(Integer) && row.fetch("source_revid") > 0 &&
    row.fetch("source_timestamp").match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
end, "audit source evidence has an invalid format")
expected_data_source = module_source(SOURCE_MODULE, runtime_data, "WITCHER_QUIZ_DATA")
expected_medium_source = module_source(MEDIUM_MODULE, runtime_medium, "WITCHER_MEDIUM_DATA")
expected_pack_source = pack_source(definitions)
EXPECTED_ARTIFACT_SHA256.each do |path, digest|
  fail_unless(Digest::SHA256.file(path).hexdigest == digest, "an audit artifact failed its checksum")
end

if ARGV == ["--check"]
  fail_unless(File.read(DATA_PATH, encoding: "UTF-8").gsub("\r\n", "\n") == expected_data_source, "generated Witcher data differs from audit inputs")
  fail_unless(File.read(MEDIUM_PATH, encoding: "UTF-8").gsub("\r\n", "\n") == expected_medium_source, "generated Witcher medium data differs from audit inputs")
  fail_unless(File.read(PACK_PATH, encoding: "UTF-8").gsub("\r\n", "\n") == expected_pack_source, "generated Witcher loader differs from audit inputs")
  puts "Witcher quiz audit verified: #{final.length} retained, #{removed.length} removed, #{edit_rows.length} edited"
elsif ARGV.empty?
  File.write(DATA_PATH, expected_data_source, encoding: "UTF-8")
  File.write(MEDIUM_PATH, expected_medium_source, encoding: "UTF-8")
  File.write(PACK_PATH, expected_pack_source, encoding: "UTF-8")
  puts "Rebuilt three Witcher sets: #{calculated.to_json}"
else
  raise "Usage: ruby tools/rebuild-audited-witcher-quiz.rb [--check]"
end
