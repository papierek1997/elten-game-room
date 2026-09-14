import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1]
RUBY = os.environ.get("RUBY", "ruby")


def write_json(path, document):
    path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def run_case(root, name, mutate, expected):
    paths = [root / "content" / filename for filename in [
        "QUIZ_WITCHER_REMOVALS.json", "QUIZ_WITCHER_EDITS.json", "QUIZ_WITCHER_AUDIT_LEDGER.json",
        "QUIZ_IMPORT_REPORT.json", "quiz_witcher_pl_data.rb", "quiz_witcher_pl_medium_data.rb", "quiz_witcher_pl.rb",
    ]]
    paths += list((root / "content" / "witcher_audit_reports").glob("*.json"))
    backups = {path: path.read_bytes() for path in paths}
    try:
        mutate(root)
        result = subprocess.run([RUBY, "tools/rebuild-audited-witcher-quiz.rb", "--check"], cwd=root, text=True, capture_output=True)
        output = result.stdout + result.stderr
        if result.returncode == 0 or expected not in output:
            raise AssertionError(f"{name} did not fail closed as expected: {result.returncode}\n{output}")
        print(f"PASS {name}: {expected}")
    finally:
        for path, content in backups.items():
            path.write_bytes(content)


with tempfile.TemporaryDirectory(prefix="witcher-audit-negative-") as directory:
    root = Path(directory) / "repo"
    shutil.copytree(SOURCE, root)

    def missing_level(root):
        path = root / "content" / "QUIZ_WITCHER_REMOVALS.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        document["removals"][0]["original"].pop("level")
        write_json(path, document)
    run_case(root, "incomplete removal snapshot", missing_level, "removal snapshot differs from the pinned base")

    def no_op_edit(root):
        path = root / "content" / "QUIZ_WITCHER_EDITS.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        document["edits"][0]["replacement"] = document["edits"][0]["original"]
        write_json(path, document)
    run_case(root, "no-op edit", no_op_edit, "an edit does not change its original")

    def medium_conflict(root):
        path = root / "content" / "QUIZ_WITCHER_EDITS.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        document["edits"][0]["replacement"]["prompt"] = "Kontrola — pytanie w grach z serii Wiedźmin?"
        document["edits"][0]["replacement"]["medium_code"] = "b"
        write_json(path, document)
    run_case(root, "prompt and medium conflict", medium_conflict, "an edit contradicts its medium")

    def swapped_ledger_outcomes(root):
        path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        removed = next(row for row in document["question_checks"] if row["outcome"] == "remove")
        kept = next(row for row in document["question_checks"] if row["outcome"] == "keep")
        removed["outcome"], kept["outcome"] = kept["outcome"], removed["outcome"]
        write_json(path, document)
    run_case(root, "swapped per-ID ledger outcomes", swapped_ledger_outcomes, "a ledger outcome differs from its manifest")

    def lost_source_link(root):
        path = root / "content" / "quiz_witcher_pl_data.rb"
        text = path.read_text(encoding="utf-8")
        text = text.replace('      "source_links": [\n', '      "lost_source_links": [\n', 1)
        path.write_text(text, encoding="utf-8")
    run_case(root, "lost generated source link", lost_source_link, "generated Witcher data differs from audit inputs")

    def forged_report_hash(root):
        path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        document["report_manifest"]["geografia"]["sha256"] = "0" * 64
        write_json(path, document)
    run_case(root, "forged canonical report hash", forged_report_hash, "a canonical audit report failed its checksum")

    def forged_report_counts(root):
        report_path = root / "content" / "witcher_audit_reports" / "geografia.json"
        report = json.loads(report_path.read_text(encoding="utf-8"))
        report["checked_questions"] -= 1
        write_json(report_path, report)
        ledger_path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        ledger["report_manifest"]["geografia"]["checked_questions"] -= 1
        ledger["report_manifest"]["geografia"]["sha256"] = __import__("hashlib").sha256(report_path.read_bytes()).hexdigest()
        write_json(ledger_path, ledger)
    run_case(root, "forged report counts and matching hash", forged_report_counts, "a canonical audit report failed its checksum")

    def forged_policy_count(root):
        path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        document["policy_manifest"]["parent_schema_policy"]["question_count"] += 1
        write_json(path, document)
    run_case(root, "forged policy count", forged_policy_count, "audit policy count is invalid")

    def forged_schema_coverage(root):
        report_path = root / "content" / "witcher_audit_reports" / "schemas.json"
        report = json.loads(report_path.read_text(encoding="utf-8"))
        report["schemas"][0]["affected_ids"].pop()
        write_json(report_path, report)
        ledger_path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        ledger["schema_review"] = report
        ledger["report_manifest"]["schemas"]["sha256"] = __import__("hashlib").sha256(report_path.read_bytes()).hexdigest()
        write_json(ledger_path, ledger)
    run_case(root, "forged schema coverage and matching hash", forged_schema_coverage, "a canonical audit report failed its checksum")

    def forged_finding_semantics(root):
        report_path = root / "content" / "witcher_audit_reports" / "czarodzieje.json"
        report = json.loads(report_path.read_text(encoding="utf-8"))
        finding = report["findings"][0]
        finding["action"] = "edit" if finding["action"] != "edit" else "remove"
        finding["reason_codes"] = ["forged"]
        finding["reason"] = "Forged rationale"
        finding["evidence_urls"] = ["https://example.com/forged"]
        write_json(report_path, report)
        ledger_path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        ledger["report_manifest"]["czarodzieje"]["sha256"] = __import__("hashlib").sha256(report_path.read_bytes()).hexdigest()
        write_json(ledger_path, ledger)
    run_case(root, "forged finding semantics and matching hash", forged_finding_semantics, "a canonical audit report failed its checksum")

    def forged_partition_input_count(root):
        report_path = root / "content" / "witcher_audit_reports" / "geografia.json"
        report = json.loads(report_path.read_text(encoding="utf-8"))
        report["input_count"] = 1
        write_json(report_path, report)
        ledger_path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        ledger["report_manifest"]["geografia"]["input_count"] = 1
        ledger["report_manifest"]["geografia"]["sha256"] = __import__("hashlib").sha256(report_path.read_bytes()).hexdigest()
        write_json(ledger_path, ledger)
    run_case(root, "forged partition input count", forged_partition_input_count, "a canonical audit report failed its checksum")

    def foreign_crosscut_id(root):
        report_path = root / "content" / "witcher_audit_reports" / "crosscut.json"
        report = json.loads(report_path.read_text(encoding="utf-8"))
        report["findings"][0]["id"] = "not-a-base-id"
        write_json(report_path, report)
        ledger_path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        ledger["report_manifest"]["crosscut"]["sha256"] = __import__("hashlib").sha256(report_path.read_bytes()).hexdigest()
        write_json(ledger_path, ledger)
    run_case(root, "foreign cross-cutting finding ID", foreign_crosscut_id, "a canonical audit report failed its checksum")

    def forged_source_provenance(root):
        report_path = root / "content" / "witcher_audit_reports" / "czarodzieje.json"
        report = json.loads(report_path.read_text(encoding="utf-8"))
        row = report["checks"][0]
        row.update({"source_url": "https://wiedzmin.fandom.com/wiki/Forged", "source_revid": 1, "source_timestamp": "2026-09-14T00:00:00Z"})
        write_json(report_path, report)
        ledger_path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        ledger_row = next(item for item in ledger["question_checks"] if item["id"] == row["id"])
        ledger_row.update({"source_url": row["source_url"], "source_revid": 1, "source_timestamp": row["source_timestamp"]})
        ledger["report_manifest"]["czarodzieje"]["sha256"] = __import__("hashlib").sha256(report_path.read_bytes()).hexdigest()
        write_json(ledger_path, ledger)
    run_case(root, "coordinated forged source provenance", forged_source_provenance, "a canonical audit report failed its checksum")

    def forged_policy(root):
        path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        document["policy_manifest"]["forged_policy"] = {"description": "forged", "question_count": 0}
        write_json(path, document)
    run_case(root, "unknown audit policy", forged_policy, "audit policy manifest contains an unknown policy")

    def missing_additional_schema_key(root):
        path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        document["policy_manifest"]["parent_schema_policy"]["additional_schema_keys"].pop()
        write_json(path, document)
    run_case(root, "missing additional schema key", missing_additional_schema_key, "parent schema policy has invalid exceptions")

    def missing_parent_reference(root):
        removal_path = root / "content" / "QUIZ_WITCHER_REMOVALS.json"
        removals = json.loads(removal_path.read_text(encoding="utf-8"))
        row = next(item for item in removals["removals"] if item["reports"] == ["parent_schema_policy"])
        row["reports"] = []
        write_json(removal_path, removals)
        ledger_path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        ledger_row = next(item for item in ledger["question_checks"] if item["id"] == row["id"])
        ledger_row["reports"] = []
        ledger["policy_manifest"]["parent_schema_policy"]["question_count"] -= 1
        write_json(ledger_path, ledger)
    run_case(root, "missing parent schema reference", missing_parent_reference, "parent schema policy coverage is invalid")

    def forged_data_version(root):
        path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        document["data_version"] = 99
        write_json(path, document)
    run_case(root, "forged audit data version", forged_data_version, "audit data version is invalid")

    def forged_snapshot(root):
        for filename in ["QUIZ_WITCHER_REMOVALS.json", "QUIZ_WITCHER_EDITS.json", "QUIZ_WITCHER_AUDIT_LEDGER.json"]:
            path = root / "content" / filename
            document = json.loads(path.read_text(encoding="utf-8"))
            document["wiki_snapshot"] = "invalid"
            if "summary" in document:
                document["summary"]["wiki_snapshot"] = "invalid"
            write_json(path, document)
    run_case(root, "coordinated forged source snapshot", forged_snapshot, "audit inputs use an invalid source snapshot")

    def coordinated_extra_rationale(root):
        removal_path = root / "content" / "QUIZ_WITCHER_REMOVALS.json"
        removals = json.loads(removal_path.read_text(encoding="utf-8"))
        row = removals["removals"][0]
        row["reasons"].append("Forged extra rationale")
        row["evidence_urls"].append("https://example.com/forged")
        write_json(removal_path, removals)
        ledger_path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        ledger_row = next(item for item in ledger["question_checks"] if item["id"] == row["id"])
        ledger_row["reasons"] = row["reasons"]
        ledger_row["evidence_urls"] = row["evidence_urls"]
        write_json(ledger_path, ledger)
    run_case(root, "coordinated extra manifest rationale", coordinated_extra_rationale, "an audit artifact failed its checksum")

    def forged_import_report(root):
        path = root / "content" / "QUIZ_IMPORT_REPORT.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        document["packs"]["quiz.witcher.pl"]["audited_kept"] += 1
        write_json(path, document)
    run_case(root, "forged import report", forged_import_report, "an audit artifact failed its checksum")

    def forged_ledger_reason(root):
        path = root / "content" / "QUIZ_WITCHER_AUDIT_LEDGER.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        row = next(item for item in document["question_checks"] if item["outcome"] == "remove")
        row["reason_codes"] = ["forged"]
        write_json(path, document)
    run_case(root, "forged per-ID ledger rationale", forged_ledger_reason, "a ledger rationale differs from its decision")

    def missing_removal_rationale(root):
        path = root / "content" / "QUIZ_WITCHER_REMOVALS.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        document["removals"][0]["reasons"] = []
        write_json(path, document)
    run_case(root, "missing removal rationale", missing_removal_rationale, "a manifest decision has no rationale")

    def missing_removal_evidence(root):
        path = root / "content" / "QUIZ_WITCHER_REMOVALS.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        document["removals"][0]["evidence_urls"] = []
        write_json(path, document)
    run_case(root, "missing removal source evidence", missing_removal_evidence, "a manifest decision omits its source URL")

    def missing_edit_trace(root):
        path = root / "content" / "QUIZ_WITCHER_EDITS.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        document["edits"][0]["replacement_report"] = None
        write_json(path, document)
    run_case(root, "missing edit replacement report", missing_edit_trace, "audit summary edit_reports is invalid")

    def forged_summary_breakdown(root):
        for filename in ["QUIZ_WITCHER_REMOVALS.json", "QUIZ_WITCHER_EDITS.json"]:
            path = root / "content" / filename
            document = json.loads(path.read_text(encoding="utf-8"))
            document["summary"]["remaining_by_medium"]["g"] += 1
            write_json(path, document)
    run_case(root, "forged summary breakdown", forged_summary_breakdown, "audit summary remaining_by_medium is invalid")

print("All 25 negative builder mutations were rejected")
