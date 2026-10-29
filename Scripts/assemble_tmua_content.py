#!/usr/bin/env python3
"""Validate the private TMUA content workspace and assemble the app's question bank.

The public iOS repository contains this script, the syllabus taxonomy and the
content policy, but never question content. Question JSON lives in a separate
private workspace (default: ../revisr-content-private relative to the repo).

Distributions:
  internal  Every structurally valid item is bundled with its review state so
            development builds can exercise the full journey. Items stay
            labelled as unreviewed in the app.
  public    Only items listed in the private workspace's approved-content
            manifest (approved/manifest.json) are bundled, and only when the
            manifest, the human review register and any rights grant agree on
            the exact version and its content hash. With no manifest, or an
            empty one, the public bank is empty. Restricted legacy PDFs and
            videos are removed from the built product and the result is
            re-checked.

Usage:
  assemble_tmua_content.py validate [--content DIR]
  assemble_tmua_content.py assemble --distribution internal|public --output FILE [--content DIR]
  assemble_tmua_content.py strip-restricted --app DIR --repo DIR
  assemble_tmua_content.py check-app --app DIR --repo DIR --distribution internal|public
  assemble_tmua_content.py content-hash --content DIR ID@vN   (print one version's content hash)
  assemble_tmua_content.py xcode     (build-phase entry point; reads Xcode environment)
"""

import hashlib
import json
import os
import re
import sys

SCHEMA_VERSION = 1
POLICY_VERSION = "tmua-content-policy-v2"
APPROVAL_POLICY_VERSION = "revisr-approval-policy-v1"
MANIFEST_SCHEMA = 1
MANIFEST_PATH = os.path.join("approved", "manifest.json")
CATEGORIES = {"revisr_original", "licensed_past_paper", "licensed_mock", "past_paper_study_copy", "development_fixture"}
RIGHTS_STATES = {"cleared", "pending_review", "not_permitted", "not_applicable"}
RIGHTS_FIELDS = ["inAppUse", "redistribution", "commercialUse", "answerKey", "solution"]
MATH_REVIEW = {"none", "ai_derivation_only", "human_approved", "rejected"}
ORIGINALITY_REVIEW = {"pending", "human_approved", "rejected", "not_applicable"}
PUBLICATION = {"not_approved", "approved", "withdrawn"}
STABLE_ID = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
RESTRICTED_SOURCE_DIRS = ["AdmissionsPapers", "AdmissionsSolutions", "AdmissionsVideos"]
BANK_FILENAME = "RevisrContentBank.json"

# What a student sees and is marked on. Review decisions bind to this hash, so any change to
# these fields after a decision needs a new version. Difficulty and minutes are estimates that
# reviewers may revise and are deliberately outside it.
CONTENT_FIELDS = ("stableId", "version", "paper", "category", "title", "stem", "options", "correctOptionId",
                  "solution", "taxonomy", "source", "presentation")

# Human review stages each publishable category must pass, in workflow order. The private
# review tool (revisr-content-private/tools/review_workflow.py) uses the same lists.
REVIEW_STAGES = ("mathematical", "answerKey", "workedSolution", "distractors", "wording", "syllabus",
                 "originality", "pedagogical", "rights", "publication")
REQUIRED_STAGES = {
    "revisr_original": REVIEW_STAGES,
    "licensed_past_paper": tuple(stage for stage in REVIEW_STAGES if stage != "originality"),
    "licensed_mock": tuple(stage for stage in REVIEW_STAGES if stage != "originality"),
}
PASSING_DECISIONS = {"approved", "cleared"}
AI_REVIEWER_NAMES = ("claude", "codex", "gpt", "openai", "anthropic", "assistant", "copilot", "gemini", "llm")
# Uses a licence grant must permit before a third-party item can be published, and the rights
# field each one clears.
GRANT_PERMISSIONS = {"inAppDisplay": "inAppUse", "appDistribution": "redistribution",
                     "freeAppStoreDistribution": "commercialUse", "answerOptionsAndKey": "answerKey",
                     "workedSolutions": "solution"}

# TeX commands the app's renderer (revisr/DesignSystem/MathText.swift) understands. Anything
# else would show its raw name to a student, so it fails the public format check.
RENDERER_COMMANDS = {
    "frac", "dfrac", "tfrac", "sqrt", "binom", "text", "mathrm", "textrm", "int",
    "sin", "cos", "tan", "log", "ln", "exp", "min", "max",
    "le", "leq", "ge", "geq", "ne", "neq", "lt", "gt", "pi", "theta", "alpha", "beta", "gamma", "lambda", "mu",
    "phi", "omega", "sigma", "Delta", "times", "cdot", "div", "pm", "mp", "infty", "Rightarrow", "Leftarrow",
    "iff", "to", "forall", "exists", "neg", "in", "approx", "equiv", "circ", "degree", "ldots", "dots", "cdots",
    "mid", "quad", ",", ";", " ", "{", "}", "%", "left", "right", "cup", "cap", "subset", "subseteq", "emptyset",
    "notin", "angle", "perp", "prime", "displaystyle", "textstyle", "limits", "!",
}
MATH_SPAN = re.compile(r"\\\((.*?)\\\)|\\\[(.*?)\\\]", re.S)
COMMAND = re.compile(r"\\([A-Za-z]+|.)")


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


def validate_item(item, topics, skills, root=None):
    errors = []

    def need(condition, message):
        if not condition:
            errors.append(message)

    # A question shown from its original paper has no Revisr text: the stem is empty and the
    # options carry letters only. It must point at a bundled paper region instead.
    presentation = item.get("presentation")

    stable_id = item.get("stableId", "")
    need(isinstance(stable_id, str) and STABLE_ID.match(stable_id or ""), "invalid stableId")
    need(isinstance(item.get("version"), int) and item["version"] >= 1, "invalid version")
    need(item.get("paper") in (1, 2), "paper must be 1 or 2")
    need(item.get("category") in CATEGORIES, "unknown category")
    for field in ("title", "solution") + (() if presentation else ("stem",)):
        need(isinstance(item.get(field), str) and item[field].strip(), "missing " + field)
    options = item.get("options") or []
    need(4 <= len(options) <= 8, "options must number 4 to 8")
    expected_ids = list("ABCDEFGH"[: len(options)])
    need([option.get("id") for option in options] == expected_ids, "option ids must be A, B, C, ... in order")
    if presentation:
        errors.extend(validate_presentation(item, root))
    else:
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
    if item.get("category") == "past_paper_study_copy":
        source = item.get("source") or {}
        for field in ("organisation", "examination", "paperNumber", "questionNumber"):
            need(source.get(field) not in (None, ""), "study copy missing source." + field)
        need(bool(item.get("libraryQuestionID")), "study copy missing libraryQuestionID")
        need(bool(item.get("keyProvenance")), "study copy missing keyProvenance")
        need(presentation is not None, "study copy must be shown from its paper")
        for field in RIGHTS_FIELDS:
            need((item.get("rights") or {}).get(field) != "cleared", "study copy cannot claim cleared rights." + field)
    return errors


def validate_presentation(item, root):
    """Checks a paper-presented question: its regions and, when the repository is known, that
    the paper and the official solution are bundled resources."""
    errors = []
    presentation = item.get("presentation") or {}
    document = presentation.get("document")
    regions = presentation.get("regions") or []
    if not isinstance(document, str) or not document.endswith(".pdf"):
        errors.append("presentation.document must name a bundled PDF")
    if not regions:
        errors.append("presentation needs at least one region")
    for region in regions:
        page = region.get("page")
        if not isinstance(page, int) or page < 0:
            errors.append("presentation region page must be a non-negative integer")
        if not all(isinstance(region.get(key), (int, float)) for key in ("x", "y", "width", "height")) \
                or region.get("width", 0) <= 0 or region.get("height", 0) <= 0:
            errors.append("presentation region needs a positive rectangle")
    if any(option.get("text") for option in item.get("options") or []):
        errors.append("paper-presented options carry letters only")
    if root and isinstance(document, str):
        if not os.path.isfile(os.path.join(root, "revisr", "Resources", "AdmissionsPapers", document)):
            errors.append("presentation document %s is not a bundled paper" % document)
        reference = item.get("solutionReference")
        if reference and not os.path.isfile(os.path.join(root, "revisr", "Resources", "AdmissionsSolutions",
                                                          reference.get("document", ""))):
            errors.append("solutionReference document is not a bundled solution")
    return errors


def public_gate_failures(item):
    """Every reason an item may not enter a public build. Empty means eligible."""
    failures = []
    if item.get("category") == "development_fixture":
        failures.append("development fixture")
    if item.get("category") == "past_paper_study_copy" or item.get("presentation"):
        failures.append("personal study copy, not licensed for distribution")
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


def version_key(item):
    return "%s@v%s" % (item.get("stableId"), item.get("version"))


def content_hash(item):
    """SHA-256 of the student-facing fields of one version (see CONTENT_FIELDS)."""
    canonical = json.dumps({field: item.get(field) for field in CONTENT_FIELDS}, sort_keys=True,
                           ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def normalised_stem(item):
    return re.sub(r"\s+", " ", (item.get("stem") or "").strip().lower())


def format_failures(item):
    """Reasons the app could not show an item as intended in a public build."""
    failures = []
    if item.get("presentation"):
        failures.append("shown from a bundled paper, and public builds never bundle papers")
    texts = [("stem", item.get("stem") or ""), ("solution", item.get("solution") or "")]
    texts += [("option " + str(option.get("id")), option.get("text") or "") for option in item.get("options") or []]
    for field, text in texts:
        for match in MATH_SPAN.finditer(text):
            for command in COMMAND.findall(match.group(1) if match.group(1) is not None else match.group(2)):
                if command not in RENDERER_COMMANDS:
                    failures.append("%s uses \\%s, which the app's renderer does not support" % (field, command))
        outside = MATH_SPAN.sub("", text)
        if re.search(r"\\[A-Za-z]", outside):
            failures.append("%s has a TeX command outside \\( \\), which would show as raw TeX" % field)
    if not (item.get("solution") or "").strip():
        failures.append("no worked solution")
    return failures


def is_ai_name(name):
    lowered = " %s " % (name or "").lower()
    return any(re.search(r"(^|[^a-z])%s([^a-z]|$)" % re.escape(ai), lowered) for ai in AI_REVIEWER_NAMES)


def load_json_if_present(path):
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def load_manifest(content_dir):
    return load_json_if_present(os.path.join(content_dir, MANIFEST_PATH))


def grant_covers(grant, item):
    """A grant's scope names the sources it covers; every listed field must match the item."""
    source = item.get("source") or {}
    for scope in grant.get("scope") or []:
        if all(source.get(field) == value for field, value in scope.items() if field != "questionNumbers") \
                and (not scope.get("questionNumbers") or source.get("questionNumber") in scope["questionNumbers"]):
            return True
    return False


def grant_problems(grant, reviewers):
    problems = []
    if not grant:
        return ["rights grant not found"]
    for field in ("grantId", "provider", "copyrightHolder", "licence", "attributionText", "permits", "scope", "evidence"):
        if not grant.get(field):
            problems.append("rights grant missing " + field)
    evidence = grant.get("evidence") or {}
    verifier = evidence.get("verifiedBy")
    if not verifier or verifier not in reviewers or is_ai_name((reviewers.get(verifier) or {}).get("name")):
        problems.append("rights grant evidence is not verified by a registered human")
    if not evidence.get("file") or not evidence.get("receivedOn"):
        problems.append("rights grant has no stored evidence file and date")
    if grant.get("status") != "verified":
        problems.append("rights grant status is %s" % grant.get("status"))
    return problems


def approval_problems(entry, item, register, reviewers, grant):
    """Every reason a manifest entry does not establish publication for `item`."""
    problems = []
    category = item.get("category")
    required = REQUIRED_STAGES.get(category)
    if required is None:
        return ["category %s can never be published" % category]
    digest = content_hash(item)
    if entry.get("contentHash") != digest:
        problems.append("content changed since approval (manifest hash %s, bank hash %s); a changed question "
                        "needs a new version and new decisions" % (str(entry.get("contentHash"))[:12], digest[:12]))
    recorded = ((register or {}).get("items") or {}).get(version_key(item)) or {}
    human = recorded.get("human") or {}
    for stage in required:
        approval = (entry.get("approvals") or {}).get(stage) or {}
        decision = human.get(stage) or {}
        reviewer = approval.get("reviewer")
        if approval.get("decision") not in PASSING_DECISIONS:
            problems.append("%s not approved" % stage)
            continue
        if not reviewer or reviewer not in reviewers or is_ai_name((reviewers.get(reviewer) or {}).get("name")):
            problems.append("%s approved by an unregistered or non-human reviewer" % stage)
        if (decision.get("decision"), decision.get("reviewer"), decision.get("contentHash")) != \
                (approval.get("decision"), reviewer, digest):
            problems.append("%s decision is not recorded in the review register for this exact content" % stage)
    if category in ("licensed_past_paper", "licensed_mock"):
        problems.extend(grant_problems(grant, reviewers))
        if grant and not grant_covers(grant, item):
            problems.append("rights grant %s does not cover this question" % grant.get("grantId"))
        permits = (grant or {}).get("permits") or {}
        for permission in GRANT_PERMISSIONS:
            if permits.get(permission) is not True:
                problems.append("rights grant does not permit " + permission)
    return problems


def stamp_approved(item, entry, manifest, grant, rating=None):
    """The public form of an approved item: review and rights from the manifest, no notes, and
    the independent reviewer's difficulty rating in place of the author estimate when one was
    recorded for this exact content."""
    original = item.get("category") == "revisr_original"
    review = {"mathematical": "human_approved", "originality": "human_approved" if original else "not_applicable",
              "publication": "approved", "editorialStatus": "approved", "notes": None}
    if original:
        rights = dict(item.get("rights") or {}, licence="Revisr original content",
                      attribution="Original Revisr question", **{field: "cleared" for field in RIGHTS_FIELDS})
    else:
        permits = grant.get("permits") or {}
        rights = {"copyrightHolder": grant["copyrightHolder"], "licence": grant["licence"],
                  "attribution": grant["attributionText"]}
        for permission, field in GRANT_PERMISSIONS.items():
            rights[field] = "cleared" if permits.get(permission) is True else "pending_review"
    stamped = dict(item, review=review, rights=rights)
    if rating and rating.get("contentHash") == content_hash(item) and rating.get("level") in (1, 2, 3, 4, 5):
        stamped["difficulty"] = rating["level"]
        if isinstance(rating.get("minutes"), int) and 1 <= rating["minutes"] <= 10:
            stamped["estimatedMinutes"] = rating["minutes"]
        stamped["difficultyProvenance"] = "independent reviewer's estimate; not calibrated against student responses"
    if not original:
        stamped["source"] = dict(item.get("source") or {}, attribution=grant["attributionText"])
    stamped["approval"] = {"manifestRevision": manifest.get("revision"), "policyVersion": APPROVAL_POLICY_VERSION,
                           "approvedOn": entry.get("approvedOn"), "contentHash": content_hash(stamped),
                           "stages": list(REQUIRED_STAGES[item["category"]]),
                           "rightsGrant": grant.get("grantId") if grant else None}
    # Internal provenance notes about AI assistance stay; reviewer identities never ship.
    stamped.pop("reviewers", None)
    return stamped


def public_selection(content_dir, items):
    """Approved items for a public bank. Raises SystemExit if the manifest disagrees with the
    register, the bank or a grant: a broken approval chain must stop the build, not shrink it."""
    manifest = load_manifest(content_dir)
    if not manifest:
        return [], None
    problems = []
    if manifest.get("schema") != MANIFEST_SCHEMA or manifest.get("policyVersion") != APPROVAL_POLICY_VERSION:
        problems.append("manifest schema/policy %s/%s, expected %s/%s" % (
            manifest.get("schema"), manifest.get("policyVersion"), MANIFEST_SCHEMA, APPROVAL_POLICY_VERSION))
    register = load_json_if_present(os.path.join(content_dir, "review", "register.json")) or {}
    reviewers = (load_json_if_present(os.path.join(content_dir, "review", "reviewers.json")) or {}).get("reviewers") or {}
    by_key = {version_key(item): item for item in items}
    selected = []
    for bank_name in ("approvedOriginal", "approvedLicensed"):
        for entry in manifest.get(bank_name) or []:
            item = by_key.get(entry.get("versionKey"))
            if item is None:
                problems.append("%s: not in the bank" % entry.get("versionKey"))
                continue
            expected = "approvedOriginal" if item.get("category") == "revisr_original" else "approvedLicensed"
            if bank_name != expected:
                problems.append("%s: listed under %s but its category is %s" % (entry["versionKey"], bank_name,
                                                                               item.get("category")))
            grant = None
            if entry.get("rightsGrant"):
                grant = load_json_if_present(os.path.join(content_dir, "rights", "grants", entry["rightsGrant"] + ".json"))
            reasons = approval_problems(entry, item, register, reviewers, grant)
            rating = ((((register or {}).get("items") or {}).get(version_key(item)) or {}).get("human") or {}) \
                .get("difficultyRating")
            stamped = None if reasons else stamp_approved(item, entry, manifest, grant, rating)
            if stamped is not None:
                reasons = public_gate_failures(stamped) + format_failures(stamped)
            if reasons:
                problems.append("%s: %s" % (entry["versionKey"], "; ".join(reasons)))
            else:
                selected.append(stamped)
    stems = {}
    for item in selected:
        stem = normalised_stem(item)
        if stem and stems.setdefault(stem, item["stableId"]) != item["stableId"]:
            problems.append("%s duplicates the question text of %s" % (item["stableId"], stems[stem]))
    if problems:
        for problem in problems:
            sys.stderr.write("error: approved manifest: " + problem + "\n")
        raise SystemExit(1)
    return selected, manifest.get("revision")


def validate_bank(content_dir, root):
    taxonomy_version, topics, skills = load_taxonomy(root)
    items = load_items(content_dir)
    problems = []
    seen = set()
    stems = {}
    for filename, item in items:
        key = (item.get("stableId"), item.get("version"))
        if key in seen:
            problems.append("%s: duplicate %s@v%s" % (filename, key[0], key[1]))
        seen.add(key)
        for error in validate_item(item, topics, skills, root):
            problems.append("%s: %s@v%s: %s" % (filename, key[0], key[1], error))
        # Two identities with the same question text are one question counted twice.
        stem = normalised_stem(item)
        if stem and stems.setdefault(stem, key[0]) != key[0]:
            problems.append("%s: %s@v%s repeats the question text of %s" % (filename, key[0], key[1], stems[stem]))
    return taxonomy_version, [item for _, item in items], problems


def assemble(content_dir, root, distribution, output):
    taxonomy_version, items, problems = validate_bank(content_dir, root)
    if problems:
        for problem in problems:
            sys.stderr.write("error: content: " + problem + "\n")
        raise SystemExit(1)
    manifest_revision = None
    if distribution == "public":
        selected, manifest_revision = public_selection(content_dir, items)
    else:
        selected = [item for item in items if item.get("category") != "development_fixture"]
    selected.sort(key=lambda item: (item["paper"], item["stableId"], item["version"]))
    canonical = json.dumps(selected, sort_keys=True, ensure_ascii=False).encode("utf-8")
    bank = {
        "schemaVersion": SCHEMA_VERSION,
        "bankVersion": hashlib.sha256(canonical).hexdigest()[:16],
        "distribution": distribution,
        "taxonomyVersion": taxonomy_version,
        "contentPolicyVersion": POLICY_VERSION,
        "approvedManifestRevision": manifest_revision,
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
                reasons = public_gate_failures(item) + format_failures(item)
                approval = item.get("approval") or {}
                if approval.get("contentHash") != content_hash(item) or \
                        approval.get("policyVersion") != APPROVAL_POLICY_VERSION:
                    reasons.append("no approval record matching its content")
                if reasons:
                    failures.append("%s@v%s fails public gate: %s" % (item["stableId"], item["version"], "; ".join(reasons)))
            for name in ("manifest.json", "register.json", "reviewers.json"):
                for current, _, files in os.walk(app):
                    if name in files:
                        failures.append("private review file %s bundled" % os.path.join(current, name))
    for failure in failures:
        sys.stderr.write("error: release gate: " + failure + "\n")
    if failures:
        raise SystemExit(1)
    print("Release gate passed for %s distribution" % distribution)


def default_content_dir(root):
    return os.environ.get("REVISR_PRIVATE_CONTENT_DIR") or os.path.join(os.path.dirname(root), "revisr-content-private")


def resolve_distribution(env):
    """The distribution an Xcode build may assemble. Private drafts are only
    ever bundled into Debug builds; an archive (ACTION=install), which is what
    TestFlight and the App Store receive, is always public."""
    configuration = env.get("CONFIGURATION")
    distribution = env.get("REVISR_DISTRIBUTION") or ("internal" if configuration == "Debug" else "public")
    if distribution not in ("internal", "public"):
        raise ValueError("REVISR_DISTRIBUTION must be internal or public")
    if distribution == "internal":
        if env.get("ACTION") == "install":
            raise ValueError("internal content may never be assembled for an archive; use REVISR_DISTRIBUTION=public")
        if configuration != "Debug" and env.get("REVISR_ALLOW_INTERNAL_NON_DEBUG") != "1":
            raise ValueError("internal content is limited to Debug builds (configuration %s); "
                             "set REVISR_ALLOW_INTERNAL_NON_DEBUG=1 only for a local, never-distributed build"
                             % configuration)
    return distribution


def xcode_entry():
    root = os.environ.get("SRCROOT") or repo_root()
    try:
        distribution = resolve_distribution(os.environ)
    except ValueError as error:
        sys.stderr.write("error: " + str(error) + "\n")
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
        content_dir = argument("--content", default_content_dir(root))
        approved, revision = public_selection(content_dir, items) if not problems else ([], None)
        print("%d items, %d structural problems, %d publicly eligible (approved-content manifest %s)" % (
            len(items), len(problems), len(approved), "revision %s" % revision if revision is not None else "absent"))
        raise SystemExit(1 if problems else 0)
    elif command == "assemble":
        assemble(argument("--content", default_content_dir(root)), root, argument("--distribution"), argument("--output"))
    elif command == "strip-restricted":
        strip_restricted(argument("--app"), argument("--repo", root))
    elif command == "check-app":
        check_app(argument("--app"), argument("--repo", root), argument("--distribution"))
    elif command == "content-hash":
        wanted = sys.argv[-1]
        matches = [item for _, item in load_items(argument("--content", default_content_dir(root)))
                   if version_key(item) == wanted]
        if not matches:
            raise SystemExit("unknown item version " + wanted)
        print(content_hash(matches[0]))
    else:
        sys.stderr.write(__doc__)
        raise SystemExit(2)


if __name__ == "__main__":
    main()
