#!/usr/bin/env python3
"""Build the deterministic Chunk 4 programme-only migration manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Callable, Iterable

from atomic_generation import staged_output_set


PROGRAMME_ID = "TMUA-30-DAY-2026"
START_DATE = date(2026, 8, 22)
DIAGNOSTIC_P1_SOURCE = "SRC-E29687FAAA262C5F"
DIAGNOSTIC_P2_SOURCE = "SRC-D475EB66A3CA6BF0"
OFFICIAL_SOURCE_BY_PAPER = {
    (2017, "Paper 1"): "SRC-A8EEC6FB51A7A56C",
    (2017, "Paper 2"): "SRC-E2609C48A191B76B",
    (2018, "Paper 1"): "SRC-E8D3820E6E224F11",
    (2018, "Paper 2"): "SRC-6F1EAFB9122DE1FA",
    (2019, "Paper 1"): "SRC-A64FC1F1F7B2EB61",
    (2019, "Paper 2"): "SRC-7F1E50669A41CED8",
    (2020, "Paper 1"): "SRC-71CF5BC2E344F0E3",
    (2020, "Paper 2"): "SRC-4E63F1CAF9A4E1AD",
    (2021, "Paper 1"): "SRC-774BFC53B01BF0F8",
    (2021, "Paper 2"): "SRC-631A2E1654F2FFC5",
}

DAY_DATES = {
    4: date(2026, 8, 31), 5: date(2026, 9, 1), 6: date(2026, 9, 2),
    7: date(2026, 9, 4), 8: date(2026, 9, 7), 9: date(2026, 9, 8),
    10: date(2026, 9, 9), 11: date(2026, 9, 11), 12: date(2026, 9, 14),
    13: date(2026, 9, 15), 14: date(2026, 9, 16), 15: date(2026, 9, 18),
    16: date(2026, 9, 19), 17: date(2026, 9, 21), 18: date(2026, 9, 22),
    19: date(2026, 9, 23), 20: date(2026, 9, 25), 21: date(2026, 9, 28),
    22: date(2026, 9, 29), 23: date(2026, 9, 30), 24: date(2026, 10, 2),
    25: date(2026, 10, 5), 26: date(2026, 10, 6), 27: date(2026, 10, 7),
    28: date(2026, 10, 9), 29: date(2026, 10, 12), 30: date(2026, 10, 14),
}
TUESDAY_DAYS = {5, 9, 13, 18, 22, 26}
FLEX_DATES = ["2026-09-05", "2026-09-12", "2026-09-26", "2026-10-03", "2026-10-10", "2026-10-13"]

TOPIC_GRAPHS = {"Graphs & transformations", "Exponentials & logarithms"}
TOPIC_CALCULUS = {"Integration", "Differentiation", "Graphs & transformations"}
TOPIC_PROBABILITY = {"Probability", "Statistics", "Combinatorics & counting"}
TOPIC_LOGIC = {"Logic: implication / conditions", "Functional equations & recurrences"}
TOPIC_GEOMETRY_TRIG = {"Geometry & mensuration", "Coordinate geometry", "Trigonometry"}
TOPIC_NUMBER_RATIO = {"Ratio, proportion & rates", "Number theory & divisibility", "Number & arithmetic"}
TOPIC_FUNCTIONS = {"Functional equations & recurrences", "Sequences & series", "Graphs & transformations", "Algebra: equations & inequalities"}

REVIEW_IDS = [
    "MAT-2017-Q1F", "TSPEC-P1-Q18", "TYLER-C-P1-Q07", "YOTTA-P1-Q11",
    "YOTTA-P2-Q08", "TYLER-B-P2-Q09", "TYLER-C-P1-Q05",
]


@dataclass(frozen=True)
class DayCopy:
    focus: str
    brief: str
    question_minutes: int
    review_minutes: int
    target: str
    notes: str


DAY_COPY = {
    4: DayCopy("Graphs + existing error repair", "Recall graph features, then practise transformations, asymptotes, intercepts, range and sketching. Finish by correcting graph-related errors.", 90, 45, "Sketch from structure, not appearance.", "Review: mark methods, record the initiating idea, and flag any graph still based on guessing."),
    5: DayCopy("Calculus, area + interpretation", "Repair signed-area interpretation and practise compact graph/calculus recognition rather than a broad calculus syllabus.", 75, 45, "Explain the geometry before integrating.", "Tuesday work starts after 14:00. Review signs, regions, tangent/curve order and faster recognition."),
    6: DayCopy("Statistics + probability foundations", "Build reliable probability, counting and data foundations, then finish with a short SMC efficiency set.", 85, 40, "Use systematic cases and state the sample space.", "The SMC block is deliberately short: spotting and economy, not a second syllabus."),
    7: DayCopy("Third-party Paper 1 diagnostic", "Sit the Euclid R2DREW2 Paper 1 under timed conditions, then complete a structured error and timing analysis.", 75, 75, "Complete one representative Paper 1 and analyse every loss.", "Use the local verified-page mark scheme. Do not create a result until the paper is actually attempted."),
    8: DayCopy("Paper 2 logic foundations", "Practise implication, converse, contrapositive, necessary/sufficient conditions and counterexamples with explanation-first work.", 70, 50, "State the logical form before calculating.", "Prioritise understanding and counterexamples over volume."),
    9: DayCopy("CSAT introduction", "Think aloud through a small set of unfamiliar CSAT, STEP I and MAT problems. Explain decomposition, failed approaches and adaptation.", 95, 45, "Explain the approach aloud before finalising it.", "Tuesday work starts after 14:00. This is deliberately not another TMUA multiple-choice session."),
    10: DayCopy("Geometry, coordinate geometry + trig repair", "Target circles, coordinates and efficient geometry alongside exact values, radians/degrees, periods and transformed trig graphs.", 85, 45, "Use exact structure before numerical or visual guessing.", "Review the known coordinate-geometry and trig errors explicitly."),
    11: DayCopy("Third-party Paper 2 diagnostic", "Sit the Euclid Sample Paper 2 under timed conditions, then analyse logical form, approach choice and time use.", 75, 75, "Complete one representative Paper 2 and explain each error.", "Use the local verified-page mark scheme; this is diagnostic, not an extreme challenge paper."),
    12: DayCopy("Number, ratio + bounds", "Practise ratio, scaling, bounds and number structure, then use a short SMC observation set for speed.", 75, 40, "Look for structure before expanding arithmetic.", "Retain useful ratio work while keeping the SMC segment modest."),
    13: DayCopy("Functions, graphs + recurrences", "Connect functions, transformations, sequences and recurrences, then solve two deeper CSAT-style problems with written reflection.", 85, 45, "Name the structure and recurrence before manipulating it.", "Tuesday work starts after 14:00; finish by explaining one unfamiliar problem aloud."),
    14: DayCopy("Statistics + probability intensive", "Consolidate counting, conditional probability and data interpretation, ending with a timed mixed section.", 95, 50, "Make cases exhaustive and avoid hidden double-counting.", "Mechanics is intentionally omitted because it is not the current repair priority."),
    15: DayCopy("Official TMUA 2017 Paper 1", "Sit the complete official 2017 Paper 1 under exam conditions, then review topic, timing and approach errors.", 75, 75, "Complete and fully review the official Paper 1 benchmark.", "Assignments are created now; attempts and results are recorded only when the paper is actually done."),
    16: DayCopy("Official TMUA 2017 Paper 2", "Sit the complete official 2017 Paper 2 under exam conditions and give logic/approach errors a full review.", 75, 75, "Complete and fully review the official Paper 2 benchmark.", "Paper 2 receives deliberate early benchmark exposure because it is the relative weakness."),
    17: DayCopy("Benchmark analysis + repair", "Use the current Needs Review/Redo set and known graph, trig, probability and approach weaknesses as the deterministic repair seed.", 70, 55, "Redo without looking, then write the initiating idea.", "Later benchmark-driven repair requires a plan refresh; this migration does not fabricate future performance."),
    18: DayCopy("CSAT + STEP/MAT + small BMO", "Think aloud through a small Cambridge-focused mix. State assumptions, react to hints, explain failed routes and summarise each argument.", 100, 45, "Prioritise explanation and adaptation over question count.", "Tuesday work starts after 14:00. BMO is limited to one suitable problem."),
    19: DayCopy("Official TMUA 2018 Paper 1", "Sit official 2018 Paper 1 under timed conditions and complete substantial method, error and timing review.", 75, 75, "Complete and review the official Paper 1 benchmark.", "No fake attempts or results are created by migration."),
    20: DayCopy("Official TMUA 2018 Paper 2", "Sit official 2018 Paper 2 under timed conditions and complete substantial logic, error and timing review.", 75, 75, "Complete and review the official Paper 2 benchmark.", "No fake attempts or results are created by migration."),
    21: DayCopy("Official TMUA 2019 full simulation", "Run both official 2019 papers in exam conditions with a proper break, then capture post-simulation notes and begin analysis.", 150, 90, "Complete both papers; preserve exam conditions and the break.", "This is an intentionally exceptional long day. Analysis may continue on Day 22."),
    22: DayCopy("Simulation analysis + light CSAT", "Analyse the 2019 simulation first, repair recurring topic/time/approach errors, then add only a light CSAT reasoning block.", 60, 75, "Turn each recurring error into a concrete rule or repair action.", "Tuesday work starts after 14:00. Paper analysis takes priority over the light CSAT block."),
    23: DayCopy("Hard Paper 2 mastery", "Use a coherent hard JZ/Challenge Paper 2 set for logic, counterexamples, subtle structure and pressure handling.", 90, 55, "Stay precise under stretch difficulty; stop and analyse rather than grind.", "This is a selected hard set, not a wholesale challenge bank."),
    24: DayCopy("SMC/BMO + CSAT reasoning", "Combine a short SMC speed set, two deeper BMO problems and two unfamiliar CSAT problems for controlled mathematical flexibility.", 85, 55, "Solve efficiently, then explain the deeper arguments clearly.", "TMUA remains the priority; the crossover workload is deliberately bounded."),
    25: DayCopy("Official TMUA 2020 Paper 1", "Sit official 2020 Paper 1 under timed conditions and complete substantial review.", 75, 75, "Complete and review the official Paper 1 benchmark.", "The paper remains unavailable to automatic practice before today."),
    26: DayCopy("Official TMUA 2020 Paper 2", "Sit official 2020 Paper 2 under timed conditions and complete substantial review.", 75, 75, "Complete and review the official Paper 2 benchmark.", "Tuesday work starts after 14:00; the paper remains protected before today."),
    27: DayCopy("Error repair + exam efficiency", "Repair recurring error classes and practise question selection, abandonment/return decisions, exact values and fast structural recognition.", 70, 50, "Choose a method quickly and define when to move on.", "No large fresh paper: this is controlled efficiency and repair work."),
    28: DayCopy("Official TMUA 2021 full simulation", "Run both official 2021 papers as the final exhausting simulation, with a proper break and planned analysis.", 150, 90, "Complete the final two-paper simulation under exam conditions.", "This is the last major full simulation; no result is created until the work is actually done."),
    29: DayCopy("Final targeted repair", "Use the strongest current evidence—error notes, Needs Review/Redo and recurring weak topics—for a small final repair set.", 55, 55, "Resolve remaining repeatable errors; do not chase novelty.", "Later benchmark data can replace priorities through a future explicit plan refresh."),
    30: DayCopy("Final consolidation + strategy", "Use a very small seen-question set alongside logic forms, exact trig, graph, probability, algebra and timing reminders.", 35, 55, "Finish the personal error log and exam decision rules.", "No exhausting new material. Thursday is rest; Friday is the stored exam date."),
}


def stable_hash(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
    ).hexdigest()


def slug(value: str) -> str:
    return re.sub(r"[^A-Z0-9]+", "-", value.upper()).strip("-")


class ProgrammeBuilder:
    def __init__(self, admissions: dict, solutions: dict):
        self.admissions = admissions
        self.questions = {q["externalQuestionID"]: q for q in admissions["questions"]}
        self.sources = {s["stableSourceID"]: s for s in admissions["sources"]}
        self.solution_question_ids = {link["questionID"] for link in solutions["links"]}
        self.source_questions: dict[str, list[dict]] = defaultdict(list)
        for question in admissions["questions"]:
            if question.get("sourceID"):
                self.source_questions[question["sourceID"]].append(question)
        self.old_assignments = admissions["programme"]["assignments"]
        self.old_by_question = {item["questionID"]: item for item in self.old_assignments}
        self.used = {item["questionID"] for item in self.old_assignments if item["dayNumber"] <= 3}
        self.assignments = [dict(item) for item in self.old_assignments if item["dayNumber"] <= 3]
        self.selected_by_day: dict[int, list[str]] = defaultdict(list)
        self.reused_old_d4_ids: set[str] = set()

    def useful_for(self, q: dict, stream: str) -> bool:
        return q.get("primaryPreparationStream") == stream or stream in (q.get("intendedUses") or [])

    def eligible(self, q: dict) -> bool:
        return bool(q.get("scheduleEligible")) and q.get("validityState") != "invalid" and q.get("protection") == "none"

    def select(
        self,
        *,
        day: int,
        count: int,
        block: str,
        purpose: str,
        predicate: Callable[[dict], bool],
        family_priority: Iterable[str] = (),
        target_difficulty: int = 3,
        time_cap: int = 6,
        forced: Iterable[str] = (),
        allow_forced_reuse: bool = True,
    ) -> None:
        chosen: list[dict] = []
        for identifier in forced:
            question = self.questions[identifier]
            if identifier in self.selected_by_day[day]:
                continue
            if not allow_forced_reuse and identifier in self.used:
                continue
            chosen.append(question)
        remaining = count - len(chosen)
        priorities = {family: index for index, family in enumerate(family_priority)}
        candidates = [
            q for q in self.questions.values()
            if q["externalQuestionID"] not in self.used
            and q["externalQuestionID"] not in {x["externalQuestionID"] for x in chosen}
            and self.eligible(q) and predicate(q)
        ]
        candidates.sort(key=lambda q: (
            0 if self.old_by_question.get(q["externalQuestionID"], {}).get("dayNumber") == day else 1,
            0 if q["externalQuestionID"] in self.solution_question_ids else 1,
            priorities.get(q["family"], len(priorities) + 1),
            abs(q["difficulty"] - target_difficulty),
            q["externalQuestionID"],
        ))
        chosen.extend(candidates[:remaining])
        if len(chosen) != count:
            raise ValueError(f"Day {day} block {block} selected {len(chosen)} of {count}")
        for question in chosen:
            self.add_assignment(day, question, block, purpose, time_cap)

    def add_source(self, day: int, source_id: str, block: str, purpose: str, time_cap: int = 4) -> None:
        questions = sorted(
            self.source_questions[source_id],
            key=lambda q: (q.get("questionNumber") or 10_000, q["externalQuestionID"]),
        )
        if not questions:
            raise ValueError(f"No questions resolve for {source_id}")
        for question in questions:
            if question["externalQuestionID"] in self.used:
                raise ValueError(f"Reserved paper question already used: {question['externalQuestionID']}")
            self.add_assignment(day, question, block, purpose, time_cap)

    def add_assignment(self, day: int, question: dict, block: str, purpose: str, time_cap: int) -> None:
        identifier = question["externalQuestionID"]
        old = self.old_by_question.get(identifier)
        if old and old["dayNumber"] == day and day >= 4:
            assignment_id = old["externalAssignmentID"]
            self.reused_old_d4_ids.add(assignment_id)
        else:
            assignment_id = f"{PROGRAMME_ID}-CH4-D{day:02d}-{slug(block)}-{identifier}"
        if assignment_id in {item["externalAssignmentID"] for item in self.assignments}:
            raise ValueError(f"Duplicate assignment ID {assignment_id}")
        self.assignments.append({
            "externalAssignmentID": assignment_id,
            "dayNumber": day,
            "questionID": identifier,
            "block": block,
            "purpose": purpose,
            "suggestedTimeCapMinutes": time_cap,
            "displayOrder": len(self.selected_by_day[day]),
        })
        self.selected_by_day[day].append(identifier)
        self.used.add(identifier)

    def repair_predicate(self, q: dict) -> bool:
        return self.useful_for(q, "tmua") and q.get("primaryPreparationStream") in (None, "tmua") and q["primaryTopic"] in (
            TOPIC_GRAPHS | TOPIC_GEOMETRY_TRIG | TOPIC_PROBABILITY | TOPIC_FUNCTIONS
        ) and q["family"] != "TMUA Actual"

    def build_assignments(self) -> None:
        tmua = lambda topics: lambda q: self.useful_for(q, "tmua") and q.get("primaryPreparationStream") in (None, "tmua") and q["primaryTopic"] in topics and q["family"] != "TMUA Actual"
        primary = lambda stream, topics=None: lambda q: q.get("primaryPreparationStream") == stream and (topics is None or q["primaryTopic"] in topics)
        step_i = lambda q: q["family"] == "STEP" and q.get("paper") == "STEP I" and q.get("section") == "Pure Mathematics" and "csat" in (q.get("intendedUses") or [])
        mat_csat = lambda q: q["family"] == "MAT" and ("csat" in (q.get("intendedUses") or []) or "cambridgeCSInterview" in (q.get("intendedUses") or []))

        self.select(day=4, count=12, block="Graph repair", purpose="Graph transformations, features and sketching from structure", predicate=tmua(TOPIC_GRAPHS), family_priority=["Tyler Topic Bank", "TMUA Mock", "TMUA Practice", "MAT"], forced=["MAT-2019-Q1D", "MAT-2018-Q1G"], time_cap=7)
        self.select(day=5, count=10, block="Area and calculus", purpose="Signed area, tangent/curve regions and calculus recognition", predicate=tmua(TOPIC_CALCULUS), family_priority=["Tyler Topic Bank", "TMUA Mock", "TMUA Practice", "MAT"], forced=["MAT-2020-Q1E"], time_cap=7)
        self.select(day=6, count=5, block="TMUA probability", purpose="Conditional probability, replacement and sample-space foundations", predicate=tmua({"Probability"}), family_priority=["Tyler Topic Bank", "TMUA Mock", "TMUA Practice"], time_cap=7)
        self.select(day=6, count=2, block="TMUA statistics", purpose="Means, medians, ranges and data interpretation", predicate=tmua({"Statistics"}), family_priority=["Tyler Topic Bank", "TMUA Mock", "TMUA Practice"], time_cap=7)
        self.select(day=6, count=2, block="TMUA counting", purpose="Systematic counting without hidden overlap", predicate=tmua({"Combinatorics & counting"}), family_priority=["Tyler Topic Bank", "TMUA Mock", "TMUA Practice"], time_cap=7)
        self.select(day=6, count=1, block="SMC probability", purpose="Short probability spotting segment", predicate=primary("smc", {"Probability"}), target_difficulty=2, time_cap=4)
        self.select(day=6, count=1, block="SMC statistics", purpose="Short data observation segment", predicate=primary("smc", {"Statistics"}), target_difficulty=2, time_cap=4)
        self.select(day=6, count=1, block="SMC counting", purpose="Short concise-counting segment", predicate=primary("smc", {"Combinatorics & counting"}), target_difficulty=2, time_cap=4)
        self.add_source(7, DIAGNOSTIC_P1_SOURCE, "Timed diagnostic", "Representative third-party Paper 1 diagnostic", 4)
        self.select(day=8, count=10, block="Logic foundations", purpose="Implication, necessary/sufficient conditions and counterexamples", predicate=tmua({"Logic: implication / conditions"}), family_priority=["Tyler Topic Bank", "TMUA Mock", "TMUA Practice"], time_cap=7)
        self.select(day=9, count=2, block="CSAT problems", purpose="Unfamiliar decomposition with think-aloud explanation", predicate=primary("csat"), target_difficulty=3, time_cap=22)
        self.select(day=9, count=1, block="STEP I crossover", purpose="Deep unfamiliar problem and approach explanation", predicate=step_i, target_difficulty=4, time_cap=28)
        self.select(day=9, count=1, block="MAT crossover", purpose="Longer mathematical problem-solving and adaptation", predicate=mat_csat, target_difficulty=4, time_cap=25)
        self.select(day=10, count=12, block="Geometry and trig repair", purpose="Coordinates, circles, exact values, periods and transformed trig graphs", predicate=tmua(TOPIC_GEOMETRY_TRIG), family_priority=["Tyler Topic Bank", "TMUA Mock", "TMUA Practice", "MAT"], forced=["MAT-2017-Q1F", "TSPEC-P1-Q18", "YOTTA-P2-Q08", "YOTTA-P1-Q08", "TPRA-P2-Q03"], time_cap=7)
        self.add_source(11, DIAGNOSTIC_P2_SOURCE, "Timed diagnostic", "Representative third-party Paper 2 diagnostic", 4)
        self.select(day=12, count=9, block="TMUA number and ratio", purpose="Ratio, scaling, bounds and number structure", predicate=tmua(TOPIC_NUMBER_RATIO), family_priority=["TMUA Mock", "TMUA Practice", "MAT", "Tyler Topic Bank"], time_cap=7)
        self.select(day=12, count=3, block="SMC efficiency", purpose="Short number and ratio observation segment", predicate=primary("smc", TOPIC_NUMBER_RATIO), target_difficulty=2, time_cap=4)
        self.select(day=13, count=8, block="TMUA functions", purpose="Functions, graphs, sequences and recurrence structure", predicate=tmua(TOPIC_FUNCTIONS), family_priority=["Tyler Topic Bank", "TMUA Mock", "TMUA Practice"], time_cap=7)
        self.select(day=13, count=2, block="CSAT crossover", purpose="Deeper unfamiliar problems with written reflection", predicate=primary("csat", TOPIC_FUNCTIONS | TOPIC_GRAPHS), time_cap=18)
        self.select(day=14, count=6, block="Probability intensive", purpose="Conditional probability and careful case structure", predicate=tmua({"Probability"}), family_priority=["Tyler Topic Bank", "TMUA Mock", "TMUA Practice"], time_cap=7)
        self.select(day=14, count=2, block="Statistics intensive", purpose="Data interpretation and reliable statistical reasoning", predicate=tmua({"Statistics"}), family_priority=["Tyler Topic Bank", "TMUA Mock", "TMUA Practice"], time_cap=7)
        self.select(day=14, count=4, block="Counting intensive", purpose="Systematic counting and double-counting control", predicate=tmua({"Combinatorics & counting"}), family_priority=["Tyler Topic Bank", "TMUA Mock", "TMUA Practice"], time_cap=7)
        self.select(day=14, count=1, block="SMC probability finish", purpose="Timed probability-efficiency finish", predicate=primary("smc", {"Probability"}), target_difficulty=3, time_cap=5)
        self.select(day=14, count=1, block="SMC statistics finish", purpose="Timed data-efficiency finish", predicate=primary("smc", {"Statistics"}), target_difficulty=3, time_cap=5)
        self.add_source(15, OFFICIAL_SOURCE_BY_PAPER[(2017, "Paper 1")], "Official benchmark", "Official TMUA 2017 Paper 1", 4)
        self.add_source(16, OFFICIAL_SOURCE_BY_PAPER[(2017, "Paper 2")], "Official benchmark", "Official TMUA 2017 Paper 2", 4)
        self.select(day=17, count=10, block="Deterministic repair", purpose="Current Needs Review/Redo and evidenced weak-area repair", predicate=self.repair_predicate, family_priority=["TMUA Mock", "TMUA Practice", "Tyler Topic Bank", "MAT"], forced=REVIEW_IDS, time_cap=7)
        self.select(day=18, count=2, block="CSAT reasoning", purpose="Think-aloud decomposition and explanation", predicate=primary("csat"), time_cap=22)
        self.select(day=18, count=1, block="STEP I reasoning", purpose="Explain assumptions, failed routes and final structure", predicate=step_i, target_difficulty=4, time_cap=28)
        self.select(day=18, count=1, block="MAT reasoning", purpose="Long-form mathematical adaptation", predicate=mat_csat, target_difficulty=4, time_cap=25)
        self.select(day=18, count=1, block="BMO proof", purpose="One bounded proof-structure problem", predicate=primary("bmo"), target_difficulty=4, time_cap=28)
        self.add_source(19, OFFICIAL_SOURCE_BY_PAPER[(2018, "Paper 1")], "Official benchmark", "Official TMUA 2018 Paper 1", 4)
        self.add_source(20, OFFICIAL_SOURCE_BY_PAPER[(2018, "Paper 2")], "Official benchmark", "Official TMUA 2018 Paper 2", 4)
        self.add_source(21, OFFICIAL_SOURCE_BY_PAPER[(2019, "Paper 1")], "Full simulation Paper 1", "Official TMUA 2019 Paper 1", 4)
        self.add_source(21, OFFICIAL_SOURCE_BY_PAPER[(2019, "Paper 2")], "Full simulation Paper 2", "Official TMUA 2019 Paper 2 after a proper break", 4)
        self.select(day=22, count=6, block="Simulation repair", purpose="Recurring topic, timing and approach-error repair", predicate=self.repair_predicate, family_priority=["TMUA Mock", "TMUA Practice", "Tyler Topic Bank", "MAT"], forced=["MAT-2019-Q1D", "MAT-2020-Q1E", "TSPEC-P1-Q19", "TYLER-C-P1-Q07"], time_cap=7)
        self.select(day=22, count=2, block="Light CSAT", purpose="Light unfamiliar reasoning after simulation analysis", predicate=primary("csat"), time_cap=16)
        self.select(day=23, count=6, block="JZ Paper 2 stretch", purpose="Hard logic, counterexample and algebraic-structure set", predicate=lambda q: q["family"] == "JZ Maths TMUA Mock" and "Paper 2" in (q.get("paper") or "") and q["primaryTopic"] in (TOPIC_LOGIC | {"Algebra: equations & inequalities", "Trigonometry", "Mixed / problem solving"}), target_difficulty=4, time_cap=8)
        self.select(day=23, count=6, block="Challenge Paper 2 stretch", purpose="Coherent difficult Paper 2 pressure-handling set", predicate=lambda q: q["family"] == "TMUA.fyi Challenge" and "Paper 2" in (q.get("paper") or "") and q["primaryTopic"] in (TOPIC_LOGIC | {"Algebra: equations & inequalities", "Trigonometry", "Mixed / problem solving", "Number theory & divisibility"}), time_cap=7)
        self.select(day=24, count=6, block="SMC speed", purpose="Short timed speed and efficient-observation set", predicate=primary("smc"), target_difficulty=3, time_cap=5)
        self.select(day=24, count=2, block="BMO depth", purpose="Selected proof structure and multi-step reasoning", predicate=primary("bmo"), target_difficulty=4, time_cap=24)
        self.select(day=24, count=2, block="CSAT flexibility", purpose="Unfamiliar decomposition and explanation", predicate=primary("csat"), time_cap=20)
        self.add_source(25, OFFICIAL_SOURCE_BY_PAPER[(2020, "Paper 1")], "Official benchmark", "Official TMUA 2020 Paper 1", 4)
        self.add_source(26, OFFICIAL_SOURCE_BY_PAPER[(2020, "Paper 2")], "Official benchmark", "Official TMUA 2020 Paper 2", 4)
        self.select(day=27, count=8, block="TMUA efficiency", purpose="Question selection, exact values, structural recognition and logic traps", predicate=tmua(TOPIC_GRAPHS | TOPIC_GEOMETRY_TRIG | TOPIC_PROBABILITY | TOPIC_FUNCTIONS | {"Algebra: quadratics & polynomials"}), family_priority=["TMUA Mock", "TMUA Practice", "Tyler Topic Bank"], forced=["TSPEC-P1-Q09", "TPRA-P2-Q03"], time_cap=6)
        self.select(day=27, count=2, block="SMC economy", purpose="Fast observation and decision-making", predicate=primary("smc"), target_difficulty=3, time_cap=5)
        self.add_source(28, OFFICIAL_SOURCE_BY_PAPER[(2021, "Paper 1")], "Full simulation Paper 1", "Official TMUA 2021 Paper 1", 4)
        self.add_source(28, OFFICIAL_SOURCE_BY_PAPER[(2021, "Paper 2")], "Full simulation Paper 2", "Official TMUA 2021 Paper 2 after a proper break", 4)
        self.select(day=29, count=8, block="Final repair", purpose="Current error notes and weakest remaining areas", predicate=self.repair_predicate, family_priority=["TMUA Mock", "TMUA Practice", "Tyler Topic Bank", "MAT"], forced=["MAT-2019-Q1D", "MAT-2020-Q1E", "TSPEC-P1-Q19", "TPRA-P2-Q03"], time_cap=7)
        self.select(day=30, count=6, block="Seen-question consolidation", purpose="Low-volume recall, error-log and exam-strategy consolidation", predicate=self.repair_predicate, forced=["MAT-2017-Q1F", "TSPEC-P1-Q18", "YOTTA-P1-Q11", "YOTTA-P2-Q08", "TYLER-B-P2-Q09", "TYLER-C-P1-Q07"], time_cap=6)

    def build_days(self) -> list[dict]:
        old_days = {item["dayNumber"]: item for item in self.admissions["programme"]["days"]}
        days = []
        for number in range(1, 31):
            if number <= 3:
                item = dict(old_days[number])
                item["scheduleOffsetDays"] = number - 1
                item["earliestStartMinute"] = None
            else:
                copy = DAY_COPY[number]
                item = {
                    "dayNumber": number,
                    "focus": copy.focus,
                    "studyBrief": copy.brief,
                    "allocatedQuestionCount": len(self.selected_by_day[number]),
                    "expectedQuestionMinutes": copy.question_minutes,
                    "expectedReviewMinutes": copy.review_minutes,
                    "dailyTarget": copy.target,
                    "notes": copy.notes,
                    "scheduleOffsetDays": (DAY_DATES[number] - START_DATE).days,
                    "earliestStartMinute": 840 if number in TUESDAY_DAYS else None,
                }
            days.append(item)
        return days


def build(admissions_path: Path, solutions_path: Path, output_path: Path, audit_path: Path) -> dict:
    admissions = json.loads(admissions_path.read_text())
    solutions = json.loads(solutions_path.read_text())
    if len(admissions["questions"]) != 2_600 or len(admissions["sources"]) != 136:
        raise ValueError("Chunk 4 requires the approved Chunk 3 admissions catalogue")
    builder = ProgrammeBuilder(admissions, solutions)
    builder.build_assignments()
    days = builder.build_days()
    programme = {
        "formatVersion": 1,
        "programmeID": PROGRAMME_ID,
        "baseProgrammeImportRevision": admissions["programme"]["importRevision"],
        "preserveHistoryThroughDay": 3,
        "examDate": "2026-10-16",
        "flexDates": FLEX_DATES,
        "unavailableWeekdays": ["Thursday", "Sunday"],
        "days": days,
        "assignments": builder.assignments,
    }
    programme["migrationRevision"] = stable_hash(programme)

    old_d4 = {a["externalAssignmentID"] for a in admissions["programme"]["assignments"] if a["dayNumber"] >= 4}
    new_ids = {a["externalAssignmentID"] for a in programme["assignments"]}
    question_by_id = builder.questions
    active_questions = [question_by_id[a["questionID"]] for a in programme["assignments"] if a["dayNumber"] >= 4]
    primary_counts = Counter(q.get("primaryPreparationStream") or "nil" for q in active_questions)
    intended_counts = Counter(
        stream for q in active_questions for stream in set(q.get("intendedUses") or [])
    )
    family_counts = Counter(q["family"] for q in active_questions)
    audit = {
        "migrationRevision": programme["migrationRevision"],
        "corpusCounts": {"questions": len(admissions["questions"]), "sources": len(admissions["sources"]), "solutions": len(solutions["documents"]), "links": len(solutions["links"])},
        "oldAssignments": len(admissions["programme"]["assignments"]),
        "oldD4PlusAssignments": len(old_d4),
        "oldD4PlusRetained": len(old_d4 & new_ids),
        "oldD4PlusDeactivated": len(old_d4 - new_ids),
        "newAssignments": len(new_ids - {a["externalAssignmentID"] for a in admissions["programme"]["assignments"]}),
        "finalActiveAssignments": len(programme["assignments"]),
        "finalD4PlusAssignments": sum(a["dayNumber"] >= 4 for a in programme["assignments"]),
        "primaryStreamAssignmentsD4Plus": dict(sorted(primary_counts.items())),
        "intendedUseAssignmentsD4Plus": dict(sorted(intended_counts.items())),
        "familyAssignmentsD4Plus": dict(sorted(family_counts.items())),
        "questionCountsByDay": {str(d): len(builder.selected_by_day[d]) if d >= 4 else sum(a["dayNumber"] == d for a in programme["assignments"]) for d in range(1, 31)},
        "minutesByDay": {str(d["dayNumber"]): {"question": d["expectedQuestionMinutes"], "review": d["expectedReviewMinutes"], "total": d["expectedQuestionMinutes"] + d["expectedReviewMinutes"]} for d in days},
        "datesByDay": {str(d): DAY_DATES[d].isoformat() for d in DAY_DATES},
        "diagnostics": {"D7": DIAGNOSTIC_P1_SOURCE, "D11": DIAGNOSTIC_P2_SOURCE},
        "officialBenchmarks": {f"{year} {paper}": source for (year, paper), source in OFFICIAL_SOURCE_BY_PAPER.items()},
        "flexDates": FLEX_DATES,
    }

    with staged_output_set([output_path, audit_path]) as staged:
        staged[0].parent.mkdir(parents=True, exist_ok=True)
        staged[0].write_text(json.dumps(programme, indent=2, ensure_ascii=False) + "\n")
        staged[1].write_text(json.dumps(audit, indent=2, ensure_ascii=False) + "\n")
    return audit


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--admissions", type=Path, default=Path("revisr/Resources/AdmissionsManifest.json"))
    parser.add_argument("--solutions", type=Path, default=Path("revisr/Resources/AdmissionsSolutionsManifest.json"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--audit", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.admissions, args.solutions, args.output, args.audit), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
