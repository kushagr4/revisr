#!/usr/bin/env python3
"""Reports what a public Revisr build could offer from approved content, and the exact gaps.

It reads the private workspace through the assembler's own public selection, so it sees exactly
what a Release build would bundle. Output is aggregate (counts, topics, levels): it never prints
question text, keys or reviewer details.

Usage:
  public_content_readiness.py [--content DIR] [--assume FILE] [--json]

  --assume FILE  also report a hypothetical set: a file of ID@vN lines, or the private review
                 queue (review/queue.json, optionally FILE:WAVE to take waves 1..WAVE). Nothing
                 is approved by this; it only answers "what if these passed review?".
  --ai-levels    for the hypothetical set, count levels with the independent AI estimate recorded
                 in the private register where one exists (stored author levels run high).

Thresholds (see docs/R3_PUBLIC_CONTENT_PIPELINE.md for the reasoning):
  section sizes per paper: Starter 5, Quick 8 (Paper 2: 7), Balanced 10, Comprehensive 20.
  A length is offered when each paper has at least its section size. It is offered well when
  each paper also has 1.5x the section size (so students do not all get the same set), covers
  min(section size, applicable topics) topics, and has at least the selector's demanding share
  (levels 4-5) for that size.
"""
import importlib.util
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("assemble", os.path.join(HERE, "assemble_tmua_content.py"))
A = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(A)

LENGTHS = [("starter", {1: 5, 2: 5}), ("quick", {1: 8, 2: 7}), ("balanced", {1: 10, 2: 10}),
           ("comprehensive", {1: 20, 2: 20})]
# Demanding share (levels 4-5) the v3 selector aims for, by section size.
DEMANDING = [(5, 0.20), (8, 0.30), (15, 0.45), (99, 0.50)]
# Practice questions a plan uses per study day, measured by TMUACatalogueAuditTests (R2) on the
# development bank: about 3.8 (3 h over 3 days), 2.9 (5 h over 6 days) and 5.5 (12 h daily).
PLAN_LOADS = [("3h/3d", 3, 3.8), ("5h/6d", 6, 2.9), ("12h/7d", 7, 5.5)]


def demanding_share(size):
    return next(share for limit, share in DEMANDING if size <= limit)


def summarise(items, topics):
    report = {}
    for paper in (1, 2):
        pool = [item for item in items if item["paper"] == paper]
        applicable = sorted(key for key, topic in topics.items() if paper in topic["papers"])
        covered = sorted({item["taxonomy"]["topic"] for item in pool})
        levels = {level: sum(1 for item in pool if item["difficulty"] == level) for level in range(1, 6)}
        report[paper] = {"count": len(pool), "topicsCovered": len(covered), "topicsApplicable": len(applicable),
                         "missingTopics": [topic for topic in applicable if topic not in covered],
                         "levels": levels, "demanding": levels[4] + levels[5],
                         "originals": sum(1 for item in pool if item["category"] == "revisr_original"),
                         "licensed": sum(1 for item in pool if item["category"] in ("licensed_past_paper", "licensed_mock"))}
    lengths = {}
    for name, sizes in LENGTHS:
        gaps, quality = [], []
        for paper, size in sizes.items():
            paper_report = report[paper]
            if paper_report["count"] < size:
                gaps.append("Paper %d needs %d more questions" % (paper, size - paper_report["count"]))
            variety = math.ceil(1.5 * size)
            if paper_report["count"] < variety:
                quality.append("Paper %d: %d of %d for per-student variety" % (paper, paper_report["count"], variety))
            wanted_topics = min(size, paper_report["topicsApplicable"])
            if paper_report["topicsCovered"] < wanted_topics:
                quality.append("Paper %d: %d of %d topics" % (paper, paper_report["topicsCovered"], wanted_topics))
            demanding = math.ceil(demanding_share(size) * size)
            if paper_report["demanding"] < demanding:
                quality.append("Paper %d: %d of %d demanding (level 4-5)" % (paper, paper_report["demanding"], demanding))
        lengths[name] = {"offered": not gaps, "offeredWell": not gaps and not quality, "gaps": gaps, "quality": quality}
    # Fresh practice left after the longest diagnostic the set supports (it uses those questions).
    used = max([sum(sizes.values()) for name, sizes in LENGTHS if lengths[name]["offered"]] or [0])
    fresh = max(0, len(items) - used)
    plan = {label: {"freshPracticeDays": round(fresh / rate, 1), "studyDaysPerWeek": days,
                    "approxCalendarDays": round(fresh / rate / days * 7)}
            for label, days, rate in PLAN_LOADS}
    return {"papers": report, "lengths": lengths, "diagnosticQuestionsUsed": used, "freshForPractice": fresh,
            "plan": plan}


def assumed_items(spec, items):
    path, _, wave = spec.partition(":")
    by_key = {A.version_key(item): item for item in items}
    if path.endswith(".json"):
        with open(path, encoding="utf-8") as handle:
            rows = json.load(handle)["queue"]
        wanted = [row["versionKey"] for row in rows if not wave or row["wave"] <= int(wave)]
    else:
        with open(path, encoding="utf-8") as handle:
            wanted = [line.strip() for line in handle if line.strip()]
    missing = [key for key in wanted if key not in by_key]
    if missing:
        raise SystemExit("unknown versions in %s: %s" % (spec, ", ".join(missing[:5])))
    return [by_key[key] for key in wanted]


def show(title, summary):
    print("== %s" % title)
    for paper, report in summary["papers"].items():
        print("  Paper %d: %d questions (%d original, %d licensed), topics %d/%d, levels %s, demanding %d" % (
            paper, report["count"], report["originals"], report["licensed"], report["topicsCovered"],
            report["topicsApplicable"], " ".join("L%d=%d" % pair for pair in report["levels"].items()),
            report["demanding"]))
        if report["missingTopics"]:
            print("    missing topics: %s" % ", ".join(report["missingTopics"]))
    for name, verdict in summary["lengths"].items():
        state = "offered well" if verdict["offeredWell"] else "offered (thin)" if verdict["offered"] else "unavailable"
        print("  %-13s %-15s %s" % (name, state, "; ".join(verdict["gaps"] + verdict["quality"])))
    print("  after the longest supported diagnostic (%d questions), %d fresh practice questions remain:" % (
        summary["diagnosticQuestionsUsed"], summary["freshForPractice"]))
    for label, estimate in summary["plan"].items():
        print("    %-7s about %s study days (~%s calendar days) of new questions" % (
            label, estimate["freshPracticeDays"], estimate["approxCalendarDays"]))


def main():
    root = os.path.dirname(HERE)
    args = sys.argv[1:]
    content = args[args.index("--content") + 1] if "--content" in args else A.default_content_dir(root)
    _, topics, _ = A.load_taxonomy(root)
    _, items, problems = A.validate_bank(content, root)
    if problems:
        raise SystemExit("the bank has %d structural problems; run validate" % len(problems))
    approved, revision = A.public_selection(content, items)
    results = {"approvedManifestRevision": revision, "approved": summarise(approved, topics)}
    if "--assume" in args:
        spec = args[args.index("--assume") + 1]
        assumed = assumed_items(spec, items)
        if "--ai-levels" in args:
            register = A.load_json_if_present(os.path.join(content, "review", "register.json")) or {}
            entries = register.get("items") or {}

            def ai_level(item):
                entry = entries.get(A.version_key(item)) or {}
                estimate = (entry.get("aiQualityR3") or {}).get("difficultyEstimate")
                if estimate is None and entry.get("supersedes"):
                    estimate = ((entries.get(entry["supersedes"]) or {}).get("aiQualityR3") or {}).get("difficultyEstimate")
                return min(item["difficulty"], estimate) if estimate else item["difficulty"]
            assumed = [dict(item, difficulty=ai_level(item)) for item in assumed]
            spec += " (AI levels)"
        results["assumed"] = {"source": os.path.basename(spec), **summarise(assumed, topics)}
    if "--json" in args:
        print(json.dumps(results, indent=1, sort_keys=True))
        return
    show("Approved for public builds (manifest revision %s)" % revision, results["approved"])
    if "assumed" in results:
        show("Hypothetical: if %s passed every review (nothing is approved by this)" % results["assumed"]["source"],
             results["assumed"])


if __name__ == "__main__":
    main()
