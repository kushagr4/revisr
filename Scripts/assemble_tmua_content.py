#!/usr/bin/env python3
"""Validate the private TMUA content workspace and assemble the app's question bank.

The public iOS repository contains this script, the syllabus taxonomy and the
content policy, but never question content. Question JSON lives in a separate
private workspace (default: ../revisr-content-private relative to the repo).

Distributions:
  internal  Every structurally valid item is bundled with its review state so
            development builds can exercise the full journey. Items stay
            labelled as unreviewed in the app.
  public    Only items that pass every rights, review and publication gate are
            bundled. Restricted legacy PDFs and videos are removed from the
            built product and the result is re-checked.

Usage:
  assemble_tmua_content.py validate [--content DIR]
  assemble_tmua_content.py assemble --distribution internal|public --output FILE [--content DIR]
  assemble_tmua_content.py strip-restricted --app DIR --repo DIR
  assemble_tmua_content.py check-app --app DIR --repo DIR --distribution internal|public
  assemble_tmua_content.py xcode     (build-phase entry point; reads Xcode environment)
"""

import hashlib
import json
import os
import re
import sys

SCHEMA_VERSION = 1
POLICY_VERSION = "tmua-content-policy-v1"
CATEGORIES = {"revisr_original", "licensed_past_paper", "licensed_mock", "development_fixture"}
RIGHTS_STATES = {"cleared", "pending_review", "not_permitted", "not_applicable"}
RIGHTS_FIELDS = ["inAppUse", "redistribution", "commercialUse", "answerKey", "solution"]
MATH_REVIEW = {"none", "ai_derivation_only", "human_approved", "rejected"}
ORIGINALITY_REVIEW = {"pending", "human_approved", "rejected", "not_applicable"}
PUBLICATION = {"not_approved", "approved", "withdrawn"}
STABLE_ID = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
RESTRICTED_SOURCE_DIRS = ["AdmissionsPapers", "AdmissionsSolutions", "AdmissionsVideos"]
BANK_FILENAME = "RevisrContentBank.json"


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_taxonomy(root):
    path = os.path.join(root, "revisr", "Resources", "TMUASyllabus.v1.json")
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    topics = {}
    for topic in data["topics"]:
        topics[topic["key"]] = {
            "papers": set(topic["papers"]),
            "strands": {strand["key"] for strand in topic["strands"]},
        }
    skills = {skill["key"] for skill in data["skills"]}
    return data["taxonomyVersion"], topics, skills


def load_items(content_dir):
    bank_dir = os.path.join(content_dir, "bank")
    items = []
    if not os.path.isdir(bank_dir):
        return items
    for name in sorted(os.listdir(bank_dir)):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(bank_dir, name), encoding="utf-8") as handle:
            payload = json.load(handle)
        for item in payload.get("items", []):
            items.append((name, item))
    return items


def balanced_math(text):
    if text.count("\\(") != text.count("\\)") or text.count("\\[") != text.count("\\]"):
        return False
    depth = 0
    escaped = False
    for character in text:
        if escaped:
            escaped = False
            continue
        if character == "\\":
            escaped = True
        elif character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth < 0:
                return False
    return depth == 0


def validate_item(item, topics, skills):
    errors = []

    def need(condition, message):
        if not condition:
            errors.append(message)

    stable_id = item.get("stableId", "")
    need(isinstance(stable_id, str) and STABLE_ID.match(stable_id or ""), "invalid stableId")
    need(isinstance(item.get("version"), int) and item["version"] >= 1, "invalid version")
    need(item.get("paper") in (1, 2), "paper must be 1 or 2")
    need(item.get("category") in CATEGORIES, "unknown category")
    for field in ("title", "stem", "solution"):
        need(isinstance(item.get(field), str) and item[field].strip(), "missing " + field)
    options = item.get("options") or []
    need(4 <= len(options) <= 8, "options must number 4 to 8")
    expected_ids = list("ABCDEFGH"[: len(options)])
    need([option.get("id") for option in options] == expected_ids, "option ids must be A, B, C, ... in order")
    texts = [option.get("text", "").strip() for option in options]
    need(all(texts), "empty option text")
    need(len(set(texts)) == len(texts), "duplicate option text")
    need(item.get("correctOptionId") in expected_ids, "correctOptionId is not an option")
    for field in ("stem", "solution"):
        need(balanced_math(item.get(field, "")), "unbalanced math markup in " + field)
    for option in options:
        need(balanced_math(option.get("text", "")), "unbalanced math markup in option " + str(option.get("id")))
    taxonomy = item.get("taxonomy") or {}
    topic = topics.get(taxonomy.get("topic"))
    need(topic is not None, "unknown topic")
    if topic is not None:
        need(taxonomy.get("strand") in topic["strands"], "strand does not belong to topic")
        need(item.get("paper") in topic["papers"], "topic is not applicable to this paper")
    skill = taxonomy.get("skill")
    need(skill is None or skill in skills, "unknown skill")
    need(isinstance(item.get("difficulty"), int) and 1 <= item["difficulty"] <= 5, "difficulty must be 1-5")
    need(isinstance(item.get("estimatedMinutes"), int) and 1 <= item["estimatedMinutes"] <= 10,
         "estimatedMinutes must be 1-10")
    rights = item.get("rights") or {}
    for field in RIGHTS_FIELDS:
        need(rights.get(field) in RIGHTS_STATES, "invalid rights." + field)
    need(isinstance(rights.get("copyrightHolder"), str) and rights["copyrightHolder"], "missing copyrightHolder")
    need(isinstance(rights.get("licence"), str) and rights["licence"], "missing licence")
    need(isinstance(rights.get("attribution"), str) and rights["attribution"], "missing attribution")
    review = item.get("review") or {}
    need(review.get("mathematical") in MATH_REVIEW, "invalid review.mathematical")
    need(review.get("originality") in ORIGINALITY_REVIEW, "invalid review.originality")
    need(review.get("publication") in PUBLICATION, "invalid review.publication")
    if item.get("category") in ("licensed_past_paper", "licensed_mock"):
        source = item.get("source") or {}
        for field in ("organisation", "examination", "year", "paperNumber", "questionNumber", "url"):
            need(source.get(field) not in (None, ""), "licensed item missing source." + field)
    return errors


def public_gate_failures(item):
    """Every reason an item may not enter a public build. Empty means eligible."""
    failures = []
    if item.get("category") == "development_fixture":
        failures.append("development fixture")
    rights = item.get("rights") or {}
    for field in RIGHTS_FIELDS:
        if rights.get(field) != "cleared":
            failures.append("rights." + field + " is " + str(rights.get(field)))
    review = item.get("review") or {}
    if review.get("mathematical") != "human_approved":
        failures.append("mathematical review is " + str(review.get("mathematical")))
    if item.get("category") == "revisr_original" and review.get("originality") != "human_approved":
        failures.append("originality review is " + str(review.get("originality")))
    if review.get("publication") != "approved":
        failures.append("publication is " + str(review.get("publication")))
    return failures


def validate_bank(content_dir, root):
    taxonomy_version, topics, skills = load_taxonomy(root)
    items = load_items(content_dir)
    problems = []
    seen = set()
    for filename, item in items:
        key = (item.get("stableId"), item.get("version"))
        if key in seen:
            problems.append("%s: duplicate %s@v%s" % (filename, key[0], key[1]))
        seen.add(key)
        for error in validate_item(item, topics, skills):
            problems.append("%s: %s@v%s: %s" % (filename, key[0], key[1], error))
    return taxonomy_version, [item for _, item in items], problems


def assemble(content_dir, root, distribution, output):
    taxonomy_version, items, problems = validate_bank(content_dir, root)
    if problems:
        for problem in problems:
            sys.stderr.write("error: content: " + problem + "\n")
        raise SystemExit(1)
    if distribution == "public":
        selected = [item for item in items if not public_gate_failures(item)]
    else:
        selected = [item for item in items if item.get("category") != "development_fixture"]
    selected.sort(key=lambda item: (item["paper"], item["stableId"], item["version"]))
    if distribution == "public":
        # Internal reviewer notes never ship in a public bundle.
        selected = [dict(item, review=dict(item["review"], notes=None)) for item in selected]
    canonical = json.dumps(selected, sort_keys=True, ensure_ascii=False).encode("utf-8")
    bank = {
        "schemaVersion": SCHEMA_VERSION,
        "bankVersion": hashlib.sha256(canonical).hexdigest()[:16],
        "distribution": distribution,
        "taxonomyVersion": taxonomy_version,
        "contentPolicyVersion": POLICY_VERSION,
        "excludedItemCount": len(items) - len(selected),
        "items": selected,
    }
    directory = os.path.dirname(output)
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(output, "w", encoding="utf-8") as handle:
        json.dump(bank, handle, ensure_ascii=False, sort_keys=True, indent=1)
    by_category = {}
    for item in selected:
        by_category[item["category"]] = by_category.get(item["category"], 0) + 1
    print("Assembled %s bank %s: %d items %s, %d excluded" % (
        distribution, bank["bankVersion"], len(selected), json.dumps(by_category, sort_keys=True),
        bank["excludedItemCount"]))
    return bank


def restricted_names(repo):
    names = set()
    for directory in RESTRICTED_SOURCE_DIRS:
        path = os.path.join(repo, "revisr", "Resources", directory)
        if os.path.isdir(path):
            for current, _, files in os.walk(path):
                for name in files:
                    if not name.startswith("."):
                        names.add(name)
    return names


def strip_restricted(app, repo):
    removed = 0
    for name in sorted(restricted_names(repo)):
        path = os.path.join(app, name)
        if os.path.isfile(path):
            os.remove(path)
            removed += 1
    print("Removed %d restricted legacy resources from %s" % (removed, app))


def check_app(app, repo, distribution):
    failures = []
    if distribution == "public":
        present = [name for name in sorted(restricted_names(repo)) if os.path.exists(os.path.join(app, name))]
        if present:
            failures.append("%d restricted legacy resources present, e.g. %s" % (len(present), present[0]))
    bank_path = os.path.join(app, BANK_FILENAME)
    if not os.path.isfile(bank_path):
        failures.append("missing " + BANK_FILENAME)
    else:
        with open(bank_path, encoding="utf-8") as handle:
            bank = json.load(handle)
        if bank.get("distribution") != distribution:
            failures.append("bank distribution is %s, expected %s" % (bank.get("distribution"), distribution))
        if distribution == "public":
            for item in bank.get("items", []):
                reasons = public_gate_failures(item)
                if reasons:
                    failures.append("%s@v%s fails public gate: %s" % (item["stableId"], item["version"], "; ".join(reasons)))
    for failure in failures:
        sys.stderr.write("error: release gate: " + failure + "\n")
    if failures:
        raise SystemExit(1)
    print("Release gate passed for %s distribution" % distribution)


def default_content_dir(root):
    return os.environ.get("REVISR_PRIVATE_CONTENT_DIR") or os.path.join(os.path.dirname(root), "revisr-content-private")


def xcode_entry():
    root = os.environ.get("SRCROOT") or repo_root()
    distribution = os.environ.get("REVISR_DISTRIBUTION") or (
        "internal" if os.environ.get("CONFIGURATION") == "Debug" else "public")
    if distribution not in ("internal", "public"):
        sys.stderr.write("error: REVISR_DISTRIBUTION must be internal or public\n")
        raise SystemExit(1)
    app = os.path.join(os.environ["TARGET_BUILD_DIR"], os.environ["UNLOCALIZED_RESOURCES_FOLDER_PATH"])
    content_dir = default_content_dir(root)
    if not os.path.isdir(os.path.join(content_dir, "bank")):
        sys.stderr.write("warning: private content workspace not found at %s; bundling an empty bank\n" % content_dir)
    assemble(content_dir, root, distribution, os.path.join(app, BANK_FILENAME))
    if distribution == "public":
        strip_restricted(app, root)
    check_app(app, root, distribution)


def argument(name, default=None):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    return default


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "validate"
    root = repo_root()
    if command == "xcode":
        xcode_entry()
    elif command == "validate":
        _, items, problems = validate_bank(argument("--content", default_content_dir(root)), root)
        for problem in problems:
            print("error: " + problem)
        eligible = [item for item in items if not public_gate_failures(item)]
        print("%d items, %d structural problems, %d publicly eligible" % (len(items), len(problems), len(eligible)))
        raise SystemExit(1 if problems else 0)
    elif command == "assemble":
        assemble(argument("--content", default_content_dir(root)), root, argument("--distribution"), argument("--output"))
    elif command == "strip-restricted":
        strip_restricted(argument("--app"), argument("--repo", root))
    elif command == "check-app":
        check_app(argument("--app"), argument("--repo", root), argument("--distribution"))
    else:
        sys.stderr.write(__doc__)
        raise SystemExit(2)


if __name__ == "__main__":
    main()
