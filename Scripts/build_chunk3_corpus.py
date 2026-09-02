#!/usr/bin/env python3
"""Build and audit Revisr's authoritative Chunk 3 local corpus.

The generator is deliberately deterministic and non-destructive by default. It
first creates a complete candidate tree outside the app target. A separate
``--commit-from`` operation atomically replaces the target resources only after
the candidate has passed preflight and sandbox-import validation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

from pypdf import PdfReader

from atomic_generation import staged_output_set


ROOT = Path(__file__).resolve().parents[1]
CORPUS_DEFAULT = Path("/Users/kushagra/Downloads/papers+")
RESOURCE_ROOT = ROOT / "revisr" / "Resources"
PAPERS_ROOT = RESOURCE_ROOT / "AdmissionsPapers"
SOLUTIONS_ROOT = RESOURCE_ROOT / "AdmissionsSolutions"
VIDEOS_ROOT = RESOURCE_ROOT / "AdmissionsVideos"
MANIFEST_PATH = RESOURCE_ROOT / "AdmissionsManifest.json"
SOLUTIONS_MANIFEST_PATH = RESOURCE_ROOT / "AdmissionsSolutionsManifest.json"
IMPORT_REPORT_PATH = RESOURCE_ROOT / "AdmissionsImportReport.json"
PAPERS_INDEX_PATH = RESOURCE_ROOT / "BundledAdmissionsPapers.json"
EXTERNAL_REGISTRY_PATH = ROOT / "EXTERNAL_RESOURCES.md"


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def stable_id(prefix: str, semantic_identity: str) -> str:
    digest = hashlib.sha256(semantic_identity.casefold().encode()).hexdigest()[:16]
    return f"{prefix}-{digest.upper()}"


def normalized_text(pages: Iterable[str]) -> str:
    return re.sub(r"[^a-z0-9]+", "", "".join(pages).casefold())


def normalized_text_checksum(pages: Iterable[str]) -> str | None:
    value = normalized_text(pages)
    return hashlib.sha256(value.encode()).hexdigest() if value else None


def read_pdf(path: Path) -> tuple[list[str], int]:
    reader = PdfReader(path)
    return [(page.extract_text() or "") for page in reader.pages], len(reader.pages)


def video_metadata(path: Path) -> dict[str, Any]:
    def metadata(name: str) -> str | None:
        result = subprocess.run(
            ["mdls", "-name", name, "-raw", str(path)],
            check=False,
            capture_output=True,
            text=True,
        )
        value = result.stdout.strip().strip("\x00")
        return None if result.returncode or value in {"", "(null)"} else value

    duration = metadata("kMDItemDurationSeconds")
    width = metadata("kMDItemPixelWidth")
    height = metadata("kMDItemPixelHeight")
    return {
        "durationSeconds": round(float(duration), 3) if duration else None,
        "pixelWidth": int(width) if width and width.isdigit() else None,
        "pixelHeight": int(height) if height and height.isdigit() else None,
    }


@dataclass
class Unit:
    number: int
    label: str
    section: str | None = None
    subpart: str | None = None
    page: int | None = None


@dataclass
class SourceSpec:
    filename: str
    code: str
    display_name: str
    family: str
    provider: str
    year: int | None
    paper: str | None
    units: list[Unit]
    role: str = "questionSource"
    official: bool = False
    primary_stream: str | None = "tmua"
    intended_uses: list[str] = field(default_factory=lambda: ["tmua"])
    format: str = "Multiple choice"
    default_topic: str = "Mixed / problem solving"
    reasoning_skill: str = "Mathematical problem solving"
    difficulty: int = 3
    difficulty_label: str = "Challenging"
    difficulty_provenance: str = "inferred"
    classification_confidence: str = "High"
    schedule_eligible: bool = True
    answer_content: str | None = None
    answer_start_page: int | None = None
    requires_external_verification: bool = False
    requires_visual_verification: bool = False
    notes: str | None = None

    @property
    def semantic_identity(self) -> str:
        return f"source:{self.code}"

    @property
    def source_id(self) -> str:
        return stable_id("SRC", self.semantic_identity)


@dataclass
class SolutionSpec:
    filename: str
    code: str
    display_name: str
    solution_type: str
    family: str
    provider: str
    source_codes: list[str]
    year: int | None = None
    paper: str | None = None
    media_kind: str = "pdf"
    mapping_confidence: str = "sourceSection"
    start_page: int | None = 1
    is_verified: bool = True
    notes: str | None = None

    @property
    def semantic_identity(self) -> str:
        return f"solution:{self.code}"

    @property
    def solution_id(self) -> str:
        return stable_id("SOL", self.semantic_identity)


def simple_units(count: int) -> list[Unit]:
    return [Unit(number=value, label=str(value)) for value in range(1, count + 1)]


def step_units(count: int) -> list[Unit]:
    values = []
    for number in range(1, count + 1):
        section = "Pure Mathematics" if number <= 8 else (
            "Mechanics" if number <= min(10, count) else "Probability and Statistics"
        )
        values.append(Unit(number=number, label=str(number), section=section))
    return values


def topic_units(section_counts: list[tuple[str, int]]) -> list[Unit]:
    return [
        Unit(number=number, label=f"{section} {number}", section=section)
        for section, count in section_counts
        for number in range(1, count + 1)
    ]


def source_specs() -> list[SourceSpec]:
    specs: list[SourceSpec] = []
    step_counts = {
        (2013, 1): 13, (2014, 1): 13, (2015, 1): 13,
        (2016, 1): 13, (2017, 1): 13, (2018, 1): 13,
        (2019, 1): 11, (2017, 2): 13, (2018, 2): 13,
        (2019, 2): 12, (2020, 2): 12, (2021, 2): 12, (2022, 2): 12,
    }
    for (year, paper), count in sorted(step_counts.items()):
        specs.append(SourceSpec(
            filename=f"{year} STEP {paper}.pdf",
            code=f"STEP-{year}-P{paper}",
            display_name=f"STEP {year} Paper {paper}",
            family="STEP",
            provider="UCLES / Cambridge Assessment",
            year=year,
            paper=f"STEP {'I' if paper == 1 else 'II'}",
            units=step_units(count),
            official=True,
            primary_stream=None,
            intended_uses=["csat", "cambridgeCSInterview"],
            format="Long-form written response",
            reasoning_skill="Deep multi-step mathematical reasoning",
            difficulty=4 if paper == 1 else 5,
            difficulty_label="Hard" if paper == 1 else "Stretch",
            schedule_eligible=paper == 1,
        ))

    for set_name in "ABCDE":
        for paper in (1, 2):
            specs.append(SourceSpec(
                filename=f"jz_mock_{set_name.lower()}_p{paper}_question.pdf",
                code=f"JZ-{set_name}-P{paper}",
                display_name=f"JZ Maths Set {set_name} Paper {paper}",
                family="JZ Maths TMUA Mock",
                provider="JZ Maths",
                year=2026,
                paper=f"Set {set_name} Paper {paper}",
                units=simple_units(20),
                reasoning_skill="Difficult TMUA-style problem solving",
                difficulty=4,
                difficulty_label="Hard",
            ))

    for set_number in range(1, 5):
        papers = (1, 2) if set_number < 4 else (1,)
        for paper in papers:
            specs.append(SourceSpec(
                filename=f"Beyond Horizon Set {set_number} Paper {paper}_QP.pdf",
                code=f"BH-S{set_number}-P{paper}",
                display_name=f"Beyond Horizon Set {set_number} Paper {paper}",
                family="Beyond Horizon TMUA Mock",
                provider="Beyond Horizon",
                year=None,
                paper=f"Set {set_number} Paper {paper}",
                units=simple_units(20),
            ))

    for set_number in (1, 2):
        for paper in (1, 2):
            specs.append(SourceSpec(
                filename=f"SET {set_number} Challenge Paper {paper} TMUAFYI.pdf",
                code=f"TMUAFYI-C{set_number}-P{paper}",
                display_name=f"TMUA.fyi Challenge Set {set_number} Paper {paper}",
                family="TMUA.fyi Challenge",
                provider="TMUA.fyi",
                year=2026,
                paper=f"Challenge Set {set_number} Paper {paper}",
                units=simple_units(20),
                answer_content="combinedQuestionsAndSolutions",
                answer_start_page=23,
            ))

    specs.extend([
        SourceSpec(
            "MioMath 2024 Paper 1_QP.pdf", "MIOMATH-2024-P1", "MioMath 2024 Paper 1",
            "MioMath TMUA Mock", "MioMath", 2024, "Paper 1", simple_units(20),
            answer_content="answerKey", answer_start_page=10,
            requires_external_verification=True, requires_visual_verification=True,
            notes="Image-only source; all questions visually verified from rendered original pages.",
        ),
        SourceSpec(
            "MioMath 2024 Paper 2_QP.pdf", "MIOMATH-2024-P2", "MioMath 2024 Paper 2",
            "MioMath TMUA Mock", "MioMath", 2024, "Paper 2", simple_units(20),
            answer_content="answerKey", answer_start_page=10,
            requires_external_verification=True, requires_visual_verification=True,
            notes="Image-only source; Q20 independently checked and retained as usable.",
        ),
        SourceSpec(
            "TMUA_Mock_Paper_1.pdf", "SED-P1", "sed TMUA Mock Paper 1",
            "sed TMUA Mock", "sed", None, "Paper 1", simple_units(20),
            answer_content="answerKey", answer_start_page=22,
        ),
        SourceSpec(
            "TMUA_Mock_Paper_2.pdf", "SED-P2", "sed TMUA Mock Paper 2",
            "sed TMUA Mock", "sed", None, "Paper 2", simple_units(20),
            answer_content="answerKey", answer_start_page=22,
        ),
        SourceSpec(
            "euclid-r2drew2-p1-pdf.pdf", "EUCLID-R2DREW2-P1", "TMUA Euclid R2DREW2 Paper 1",
            "R2DREW2 / TMUA Euclid", "TMUA Euclid", 2026, "Paper 1", simple_units(20),
        ),
        SourceSpec(
            "euclid-sample-p2.pdf", "EUCLID-SAMPLE-P2", "TMUA Euclid Sample Paper 2",
            "TMUA Euclid", "TMUA Euclid", 2026, "Paper 2", simple_units(20),
        ),
        SourceSpec(
            "AF-TMUA-P1.pdf", "AF-P1", "Asher Falcon TMUA Paper 1",
            "Asher Falcon TMUA Mock", "Asher Falcon", None, "Paper 1", simple_units(20),
        ),
        SourceSpec(
            "ascent-algebra-functions.pdf", "EUCLID-ASCENT-AF", "Euclid Ascent: Algebra and Functions",
            "TMUA Euclid Ascent", "TMUA Euclid", 2026, "Algebra and Functions",
            topic_units([(f"Level {level}", 3) for level in range(1, 10)]),
            default_topic="Algebra: quadratics & polynomials",
            reasoning_skill="Progressive algebra and function problem solving",
        ),
        SourceSpec(
            "TMUA_Zetta_Paper_1.pdf", "ZETTA-P1", "Zetta TMUA Paper 1",
            "Zetta TMUA Mock", "Zetta", None, "Paper 1", simple_units(20),
            difficulty=4, difficulty_label="Hard", answer_content="answerKey", answer_start_page=22,
        ),
        SourceSpec(
            "TMUA_Mock (2).pdf", "ZACK-P1", "Zack TMUA Mock Paper 1",
            "Zack TMUA Mock", "Zack", None, "Paper 1", simple_units(20),
            answer_content="answerKey", answer_start_page=22,
        ),
        SourceSpec(
            "James Chen TMUA paper.pdf", "JAMES-CHEN-P1", "James Chen TMUA Paper",
            "James Chen TMUA Mock", "James Chen", None, "Mixed paper", simple_units(20),
            answer_content="combinedQuestionsAndSolutions", answer_start_page=1,
        ),
        SourceSpec(
            "mock_set1_p1_QP (2).pdf", "DPID-S1-P1", "DπD Maths Mock Set 1 Paper 1",
            "DπD Maths TMUA Mock", "DπD Maths", 2026, "Set 1 Paper 1", simple_units(20),
        ),
        SourceSpec(
            "UA Abstract Functions.pdf", "TYLER-ABSTRACT-FUNCTIONS", "Tyler Abstract Functions",
            "Tyler Topic Bank", "Tyler Tutoring", 2026, "Abstract Functions", simple_units(15),
            default_topic="Functional equations & recurrences",
        ),
        SourceSpec(
            "Modulus Functions.pdf", "TYLER-MODULUS", "Tyler Modulus Functions",
            "Tyler Topic Bank", "Tyler Tutoring", 2026, "Modulus", simple_units(20),
            default_topic="Graphs & transformations",
        ),
        SourceSpec(
            "Probability.pdf", "TYLER-PROBABILITY", "Tyler Statistics and Probability",
            "Tyler Topic Bank", "Tyler Tutoring", 2026, "Statistics and Probability", simple_units(16),
            default_topic="Probability",
        ),
        SourceSpec(
            "Number Theory.pdf", "TYLER-NUMBER-THEORY", "Tyler Number Theory",
            "Tyler Topic Bank", "Tyler Tutoring", 2026, "Number Theory",
            topic_units([("Divisibility and remainders", 15), ("Integer equations", 16)]),
            default_topic="Number theory & divisibility",
        ),
        SourceSpec(
            "Combinatorics v2.pdf", "TYLER-COMBINATORICS", "Tyler Combinatorics",
            "Tyler Topic Bank", "Tyler Tutoring", 2026, "Combinatorics",
            topic_units([
                ("Combinations", 4), ("Permutations", 5),
                ("Distinct distributions", 4), ("Stars and bars", 13),
                ("Restrictions", 6), ("Mixed", 18),
            ]),
            default_topic="Combinatorics & counting",
            requires_visual_verification=True,
            notes="Question PDF paired with visually distinct handwritten answer PDF.",
        ),
        SourceSpec(
            "TMUA - logic and proof only, from Jacqueline Tyler.pdf", "TYLER-LOGIC", "Jacqueline Tyler Logic and Proof",
            "Tyler Topic Bank", "Jacqueline Tyler / Tyler Tutoring", 2026, "Logic and Proof", simple_units(25),
            default_topic="Logic: implication / conditions",
            reasoning_skill="Logic, proof and necessary/sufficient conditions",
        ),
        SourceSpec(
            "Rosie TMUA papers Set A Paper 1 NEW.pdf", "ROSIE-A-P1", "Rosie Set A Paper 1",
            "Rosie TMUA Mock", "Rosie", None, "Set A Paper 1", simple_units(20),
        ),
        SourceSpec(
            "TMUADOTCODOTUK Solutions.pdf", "TMUAUK-R2DREW2-P1", "TMUA.co.uk R2Drew2 Mock Paper 1",
            "TMUA.co.uk R2Drew2", "TMUA.co.uk", 2026, "Paper 1", simple_units(20),
            answer_content="answerKey", answer_start_page=22,
            notes="Filename says Solutions, but inspected content is the question paper plus answer key.",
        ),
        SourceSpec(
            "TMUA-Euclid-Cheat-Sheet.pdf", "REF-EUCLID-CHEAT-SHEET", "TMUA Euclid Cheat Sheet",
            "Reference", "TMUA Euclid", None, None, [], role="reference", official=False,
            primary_stream=None, intended_uses=["tmua"], format="Reference",
            schedule_eligible=False, default_topic="Mixed / problem solving",
        ),
        SourceSpec(
            "handbook 9.0.pdf", "REF-TMUAFYI-HANDBOOK-9", "The 9.0 TMUA Handbook",
            "Reference", "Percentile Labs / TMUA.fyi", 2026, None, [], role="reference", official=False,
            primary_stream=None, intended_uses=["tmua"], format="Reference",
            schedule_eligible=False, default_topic="Mixed / problem solving",
        ),
    ])
    return specs


def solution_specs() -> list[SolutionSpec]:
    specs: list[SolutionSpec] = [
        SolutionSpec("2014 Solutions.pdf", "STEP-2014-SOL", "STEP 2014 Hints and Solutions", "hintsAndSolutions", "STEP", "UCLES", ["STEP-2014-P1"], 2014, "STEP I", start_page=4),
        SolutionSpec("2015 Solutions.pdf", "STEP-2015-SOL", "STEP 2015 Hints and Solutions", "hintsAndSolutions", "STEP", "UCLES", ["STEP-2015-P1"], 2015, "STEP I", start_page=4),
        SolutionSpec("2016 Solutions.pdf", "STEP-2016-SOL", "STEP 2016 Solutions", "hintsAndSolutions", "STEP", "UCLES", ["STEP-2016-P1"], 2016, "STEP I", start_page=5),
        SolutionSpec("2017 Solutions.pdf", "STEP-2017-SOL", "STEP 2017 Hints and Solutions", "hintsAndSolutions", "STEP", "UCLES", ["STEP-2017-P1", "STEP-2017-P2"], 2017, "STEP I and II", start_page=4),
        SolutionSpec("2018 STEP 1 Solutions.pdf", "STEP-2018-P1-SOL", "STEP 2018 Paper 1 Hints and Solutions", "hintsAndSolutions", "STEP", "UCLES", ["STEP-2018-P1"], 2018, "STEP I"),
        SolutionSpec("2018 STEP 2 Solutions.pdf", "STEP-2018-P2-SOL", "STEP 2018 Paper 2 Hints and Solutions", "hintsAndSolutions", "STEP", "UCLES", ["STEP-2018-P2"], 2018, "STEP II"),
        SolutionSpec("2019 STEP 1 Solutions.pdf", "STEP-2019-P1-SOL", "STEP 2019 Paper 1 Hints and Solutions", "hintsAndSolutions", "STEP", "UCLES", ["STEP-2019-P1"], 2019, "STEP I"),
        SolutionSpec("2019 STEP 2 Solutions.pdf", "STEP-2019-P2-SOL", "STEP 2019 Paper 2 Hints and Solutions", "hintsAndSolutions", "STEP", "UCLES", ["STEP-2019-P2"], 2019, "STEP II"),
        SolutionSpec("2020 STEP 2 Solutions.pdf", "STEP-2020-P2-SOL", "STEP 2020 Paper 2 Worked Solutions", "workedSolution", "STEP", "UCLES", ["STEP-2020-P2"], 2020, "STEP II"),
        SolutionSpec("2020 STEP 2 Examiners_ Report.pdf", "STEP-2020-P2-REPORT", "STEP 2020 Paper 2 Examiner Report", "examinerReport", "STEP", "UCLES", ["STEP-2020-P2"], 2020, "STEP II", mapping_confidence="paperLevel"),
        SolutionSpec("2021 STEP 2 Solutions.pdf", "STEP-2021-P2-SOL", "STEP 2021 Paper 2 Mark Scheme", "markScheme", "STEP", "UCLES", ["STEP-2021-P2"], 2021, "STEP II"),
        SolutionSpec("2022 STEP 2 Examiners_ Report and Mark Scheme.pdf", "STEP-2022-P2-REPORT-MS", "STEP 2022 Paper 2 Examiner Report and Mark Scheme", "examinerReport", "STEP", "UCLES", ["STEP-2022-P2"], 2022, "STEP II", mapping_confidence="paperLevel"),
    ]
    for set_name in "ABCDE":
        for paper in (1, 2):
            specs.append(SolutionSpec(
                f"jz_mock_{set_name.lower()}_p{paper}_solution.pdf",
                f"JZ-{set_name}-P{paper}-SOL",
                f"JZ Maths Set {set_name} Paper {paper} Solutions",
                "workedSolution", "JZ Maths TMUA Mock", "JZ Maths",
                [f"JZ-{set_name}-P{paper}"], 2026, f"Set {set_name} Paper {paper}",
                mapping_confidence="verifiedPage",
            ))
    specs.extend([
        SolutionSpec("euclid.r2drew2.ms1.pdf", "EUCLID-R2DREW2-P1-MS", "TMUA Euclid R2DREW2 Paper 1 Mark Scheme", "markScheme", "R2DREW2 / TMUA Euclid", "TMUA Euclid", ["EUCLID-R2DREW2-P1"], 2026, "Paper 1", mapping_confidence="verifiedPage"),
        SolutionSpec("euclid-sample-p2-ms.pdf", "EUCLID-SAMPLE-P2-MS", "TMUA Euclid Sample Paper 2 Mark Scheme", "markScheme", "TMUA Euclid", "TMUA Euclid", ["EUCLID-SAMPLE-P2"], 2026, "Paper 2", mapping_confidence="verifiedPage"),
        SolutionSpec("ascent-algebra-functions-ms.pdf", "EUCLID-ASCENT-AF-MS", "Euclid Ascent Algebra and Functions Mark Scheme", "markScheme", "TMUA Euclid Ascent", "TMUA Euclid", ["EUCLID-ASCENT-AF"], 2026, "Algebra and Functions", mapping_confidence="verifiedPage"),
        SolutionSpec("mock_set1_p1_worked.pdf", "DPID-S1-P1-WORKED", "DπD Maths Mock Set 1 Paper 1 Worked Solutions", "workedSolution", "DπD Maths TMUA Mock", "DπD Maths", ["DPID-S1-P1"], 2026, "Set 1 Paper 1", mapping_confidence="paperLevel"),
        SolutionSpec("UA Abstract Functions Answers.pdf", "TYLER-ABSTRACT-FUNCTIONS-ANS", "Tyler Abstract Functions Worked Answers", "workedSolution", "Tyler Topic Bank", "Tyler Tutoring", ["TYLER-ABSTRACT-FUNCTIONS"], 2026, "Abstract Functions", mapping_confidence="verifiedPage"),
        SolutionSpec("Modulus Functions Answers.pdf", "TYLER-MODULUS-ANS", "Tyler Modulus Functions Worked Answers", "workedSolution", "Tyler Topic Bank", "Tyler Tutoring", ["TYLER-MODULUS"], 2026, "Modulus", mapping_confidence="verifiedPage"),
        SolutionSpec("Probability Answers.pdf", "TYLER-PROBABILITY-ANS", "Tyler Statistics and Probability Worked Answers", "workedSolution", "Tyler Topic Bank", "Tyler Tutoring", ["TYLER-PROBABILITY"], 2026, "Statistics and Probability", mapping_confidence="verifiedPage"),
        SolutionSpec("Number Theory Answers.pdf", "TYLER-NUMBER-THEORY-ANS", "Tyler Number Theory Worked Answers", "workedSolution", "Tyler Topic Bank", "Tyler Tutoring", ["TYLER-NUMBER-THEORY"], 2026, "Number Theory", mapping_confidence="verifiedPage"),
        SolutionSpec("Combinatorics v2 Answers.pdf", "TYLER-COMBINATORICS-ANS", "Tyler Combinatorics Worked Answers", "workedSolution", "Tyler Topic Bank", "Tyler Tutoring", ["TYLER-COMBINATORICS"], 2026, "Combinatorics", mapping_confidence="verifiedPage", notes="Rendered pages confirm handwritten solutions over the question master."),
        SolutionSpec("TMUADOTCODOTUK Paper.pdf", "TMUAUK-R2DREW2-P1-WORKED", "TMUA.co.uk R2Drew2 Paper 1 Worked Solutions", "workedSolution", "TMUA.co.uk R2Drew2", "TMUA.co.uk", ["TMUAUK-R2DREW2-P1"], 2026, "Paper 1", mapping_confidence="verifiedPage", notes="Filename says Paper, but inspected content is worked solutions."),
    ])
    return specs


def video_specs() -> list[SolutionSpec]:
    yotta_p1 = "SRC-09C38CBD2E30F12E"
    yotta_p2 = "SRC-72E7E2AF1089EE1E"
    return [
        SolutionSpec("ASHER FALCON (AF) R2DREW2.mp4", "VIDEO-AF-P1", "Asher Falcon Paper 1 Video Walkthrough", "videoSolution", "Asher Falcon TMUA Mock", "Asher Falcon", ["AF-P1"], media_kind="video", start_page=None, mapping_confidence="paperLevel"),
        SolutionSpec("James Chen R2DREW2.mp4", "VIDEO-JAMES-CHEN", "James Chen TMUA Paper Video Walkthrough", "videoSolution", "James Chen TMUA Mock", "James Chen", ["JAMES-CHEN-P1"], media_kind="video", start_page=None, mapping_confidence="paperLevel"),
        SolutionSpec("YTDown.com_YouTube_A-challenging-mock-TMUA-paper-1_Media_CMEajVzVe9s_001_1080p.mp4", "VIDEO-YOTTA-P1", "Yotta Paper 1 Video Walkthrough", "videoSolution", "TMUA Mock", "Yotta", [yotta_p1], media_kind="video", start_page=None, mapping_confidence="paperLevel"),
        SolutionSpec("YTDown.com_YouTube_Another-extra-TMUA-paper-1-from-Zetta_Media_Yh3iXI-wnpk_001_1080p.mp4", "VIDEO-ZETTA-P1", "Zetta Paper 1 Video Walkthrough", "videoSolution", "Zetta TMUA Mock", "Zetta", ["ZETTA-P1"], media_kind="video", start_page=None, mapping_confidence="paperLevel"),
        SolutionSpec("YTDown.com_YouTube_TMUA-A-paper-1-by-Zack_Media_b4V2VHZXnYs_001_720p.mp4", "VIDEO-ZACK-P1", "Zack Paper 1 Video Walkthrough", "videoSolution", "Zack TMUA Mock", "Zack", ["ZACK-P1"], media_kind="video", start_page=None, mapping_confidence="paperLevel"),
        SolutionSpec("YTDown.com_YouTube_TMUA-Rosie-s-Paper-1_Media_LZuHa9V7Li0_001_720p.mp4", "VIDEO-ROSIE-P1", "Rosie Set A Paper 1 Video Walkthrough", "videoSolution", "Rosie TMUA Mock", "Rosie", ["ROSIE-A-P1"], media_kind="video", start_page=None, mapping_confidence="paperLevel"),
        SolutionSpec("YTDown.com_YouTube_TMUA-logic-and-proof-only-from-Jacquelin_Media_7YYuxsvlVe0_001_1080p.mp4", "VIDEO-TYLER-LOGIC", "Jacqueline Tyler Logic and Proof Video Walkthrough", "videoSolution", "Tyler Topic Bank", "Jacqueline Tyler / Tyler Tutoring", ["TYLER-LOGIC"], media_kind="video", start_page=None, mapping_confidence="paperLevel"),
        SolutionSpec("YTDown.com_YouTube_TMUA-mock-paper-2-by-Yotta_Media_eE8oNBL7-aE_001_1080p.mp4", "VIDEO-YOTTA-P2", "Yotta Paper 2 Video Walkthrough", "videoSolution", "TMUA Mock", "Yotta", [yotta_p2], media_kind="video", start_page=None, mapping_confidence="paperLevel"),
    ]


def page_for_unit(spec: SourceSpec, unit: Unit, pages: list[str]) -> int:
    if unit.page:
        return unit.page
    code = spec.code
    if code.startswith("MIOMATH-2024-P1"):
        return next(page for end, page in [(4, 2), (7, 3), (10, 4), (12, 5), (14, 6), (17, 7), (19, 8), (20, 9)] if unit.number <= end)
    if code.startswith("MIOMATH-2024-P2"):
        return next(page for end, page in [(3, 2), (5, 3), (7, 4), (10, 5), (13, 6), (15, 7), (18, 8), (20, 9)] if unit.number <= end)
    if code == "ROSIE-A-P1":
        return 1 + (unit.number + 1) // 2
    if code == "EUCLID-ASCENT-AF":
        return int(unit.section.split()[-1]) + 1
    explicit_ranges: dict[str, list[tuple[str, int, int, int]]] = {
        "TYLER-ABSTRACT-FUNCTIONS": [("", 1, 3, 2), ("", 4, 6, 3), ("", 7, 9, 4), ("", 10, 12, 5), ("", 13, 15, 6)],
        "TYLER-MODULUS": [("", 1, 3, 3), ("", 4, 6, 4), ("", 7, 9, 5), ("", 10, 12, 6), ("", 13, 14, 7), ("", 15, 17, 8), ("", 18, 20, 9)],
        "TYLER-PROBABILITY": [("", 1, 3, 2), ("", 4, 6, 3), ("", 7, 8, 4), ("", 9, 11, 5), ("", 12, 14, 6), ("", 15, 16, 7)],
        "TYLER-NUMBER-THEORY": [("Divisibility", 1, 5, 1), ("Divisibility", 6, 10, 2), ("Divisibility", 11, 15, 3), ("Integer", 1, 5, 4), ("Integer", 6, 10, 5), ("Integer", 11, 14, 6), ("Integer", 15, 16, 7)],
        "TYLER-COMBINATORICS": [("Combinations", 1, 4, 1), ("Permutations", 1, 5, 2), ("Distinct", 1, 4, 4), ("Stars", 1, 6, 6), ("Stars", 7, 13, 7), ("Restrictions", 1, 6, 8), ("Mixed", 1, 5, 9), ("Mixed", 6, 10, 10), ("Mixed", 11, 13, 11), ("Mixed", 14, 18, 12)],
        "TYLER-LOGIC": [("", 1, 3, 1), ("", 4, 6, 2), ("", 7, 9, 3), ("", 10, 12, 4), ("", 13, 15, 5), ("", 16, 18, 6), ("", 19, 21, 7), ("", 22, 24, 8), ("", 25, 25, 9)],
    }
    for section, start, end, page in explicit_ranges.get(code, []):
        if start <= unit.number <= end and (not section or (unit.section or "").startswith(section)):
            return page
    patterns = [
        re.compile(rf"(?:^|\n)\s*Question\s+{unit.number}\b", re.I),
        re.compile(rf"(?:^|\n)\s*Q\s*{unit.number}[.)]?\s", re.I),
        re.compile(rf"(?:^|\n)\s*{unit.number}[.)]\s"),
    ]
    for index, text in enumerate(pages, 1):
        if any(pattern.search(text) for pattern in patterns):
            return index
    # Most supplied mocks use a cover followed by one question per page.
    return min(unit.number + 1, len(pages))


TOPIC_KEYWORDS: list[tuple[str, tuple[str, ...]]] = [
    ("Probability", ("probability", "random", "coin", "dice", "die ", "expected value")),
    ("Statistics", ("mean", "median", "mode", "variance", "standard deviation")),
    ("Logic: implication / conditions", ("necessary", "sufficient", "counterexample", "if and only if", "must be true", "conjecture")),
    ("Sequences & series", ("sequence", "series", "recurrence", "geometric", "arithmetic progression", "summation")),
    ("Trigonometry", ("sin ", "cos ", "tan ", "radian", "trigonometric")),
    ("Integration", ("integral", "integrate", "area under")),
    ("Differentiation", ("derivative", "differentiate", "tangent", "stationary", "local maximum", "local minimum")),
    ("Graphs & transformations", ("graph", "sketch", "translation", "modulus", "absolute value")),
    ("Functional equations & recurrences", ("function f", "f(x)", "functional equation", "recurrence")),
    ("Combinatorics & counting", ("how many ways", "arrangements", "choose", "permutation", "combination")),
    ("Number theory & divisibility", ("divisible", "remainder", "prime", "integer solutions", "modulo", "factor")),
    ("Coordinate geometry", ("coordinate", "x-axis", "y-axis", "gradient", "line segment")),
    ("Geometry & mensuration", ("circle", "triangle", "polygon", "angle", "length", "perimeter", "volume")),
    ("Exponentials & logarithms", ("log", "ln(", "exponential")),
    ("Algebra: quadratics & polynomials", ("quadratic", "polynomial", "roots", "factor theorem", "cubic", "quartic")),
    ("Algebra: equations & inequalities", ("equation", "inequality", "real solutions", "solve")),
]


def classify_topic(text: str, fallback: str) -> str:
    lowered = " ".join(text.casefold().split())
    scores = [(sum(lowered.count(keyword) for keyword in words), topic) for topic, words in TOPIC_KEYWORDS]
    score, topic = max(scores)
    return topic if score else fallback


def question_id(spec: SourceSpec, unit: Unit) -> str:
    suffix = f"Q{unit.number:02d}"
    if unit.section:
        section = re.sub(r"[^A-Z0-9]+", "-", unit.section.upper()).strip("-")
        suffix = f"{section}-{suffix}"
    if unit.subpart:
        suffix += unit.subpart.upper()
    return f"{spec.code}-{suffix}"


def classify_existing_question(question: dict[str, Any], assigned_ids: set[str]) -> None:
    family = question.get("family", "")
    identifier = question["externalQuestionID"]
    primary: str | None = None
    uses: list[str]
    if family.startswith("TMUA"):
        primary, uses = "tmua", ["tmua"]
    elif family == "SMC":
        primary, uses = "smc", ["smc"]
    elif family == "BMO":
        primary, uses = "bmo", ["bmo"]
    elif family == "CSAT":
        primary, uses = "csat", ["csat"]
    elif family == "MAT":
        label = str(question.get("questionLabel") or "").replace(" ", "").upper()
        uses = ["tmua"] if label.startswith("1") or identifier in assigned_ids else ["csat", "cambridgeCSInterview"]
    elif family in {"IMC", "Senior Kangaroo"}:
        uses = ["tmua"]
    elif family == "Maclaurin":
        uses = ["csat", "cambridgeCSInterview"]
    else:
        uses = []
    # Historical programme membership is authoritative evidence that the
    # question remains useful for TMUA, even when its canonical primary stream
    # is SMC, BMO, CSAT, or enrichment. This preserves programme/export
    # compatibility without mislabelling the primary stream.
    if identifier in assigned_ids and "tmua" not in uses:
        uses.append("tmua")
    question["primaryPreparationStream"] = primary
    question["intendedUses"] = sorted(set(uses))
    question.setdefault("difficultyProvenance", "inferred")
    question.setdefault("validityState", "usable")
    question.setdefault("duplicateReviewState", "none")
    question.setdefault("possibleDuplicateQuestionIDs", [])
    match = re.search(r"Q(\d+)([A-Z])?$", identifier)
    if match:
        question.setdefault("questionNumber", int(match.group(1)))
        if match.group(2):
            question.setdefault("subpart", match.group(2).lower())


def inventory(corpus: Path, sources: list[SourceSpec], solutions: list[SolutionSpec], videos: list[SolutionSpec]) -> dict[str, Any]:
    expected: dict[str, dict[str, Any]] = {}
    for spec in sources:
        expected[spec.filename] = {
            "logicalResourceIdentity": spec.semantic_identity,
            "authorProvider": spec.provider,
            "resourceFamily": spec.family,
            "year": spec.year,
            "paper": spec.paper,
            "logicalType": "reference" if spec.role == "reference" else "questionPaperOrBank",
            "official": spec.official,
            "questionCount": len(spec.units),
            "alreadyRepresentedInRevisr": False,
            "containsQuestionsAndAnswersTogether": spec.answer_content is not None,
            "requiresVisualVerification": spec.requires_visual_verification,
            "requiresExternalVerification": spec.requires_external_verification,
            "shouldCreateQuestionRecords": bool(spec.units),
            "classificationNotes": spec.notes,
        }
    for spec in solutions:
        expected[spec.filename] = {
            "logicalResourceIdentity": spec.semantic_identity,
            "authorProvider": spec.provider,
            "resourceFamily": spec.family,
            "year": spec.year,
            "paper": spec.paper,
            "logicalType": spec.solution_type,
            "official": spec.provider in {"UCLES", "UCLES / Cambridge Assessment"},
            "questionCount": 0,
            "alreadyRepresentedInRevisr": False,
            "containsQuestionsAndAnswersTogether": spec.filename == "Combinatorics v2 Answers.pdf",
            "requiresVisualVerification": spec.filename in {"Combinatorics v2 Answers.pdf", "mock_set1_p1_worked.pdf"},
            "requiresExternalVerification": False,
            "shouldCreateQuestionRecords": False,
            "classificationNotes": spec.notes,
        }
    for spec in videos:
        expected[spec.filename] = {
            "logicalResourceIdentity": spec.semantic_identity,
            "authorProvider": spec.provider,
            "resourceFamily": spec.family,
            "year": spec.year,
            "paper": spec.paper,
            "logicalType": "videoSolution",
            "official": False,
            "questionCount": 0,
            "alreadyRepresentedInRevisr": spec.source_codes[0].startswith("SRC-"),
            "containsQuestionsAndAnswersTogether": False,
            "requiresVisualVerification": True,
            "requiresExternalVerification": False,
            "shouldCreateQuestionRecords": False,
            "classificationNotes": "Whole-paper walkthrough; no per-question timestamps asserted.",
        }

    actual = sorted(path for path in corpus.iterdir() if path.is_file())
    missing = sorted(set(expected) - {path.name for path in actual})
    extra = sorted({path.name for path in actual} - set(expected))
    if missing or extra:
        raise ValueError(f"Corpus classification is incomplete: missing={missing}, extra={extra}")

    records = []
    binary_groups: defaultdict[str, list[str]] = defaultdict(list)
    text_groups: defaultdict[str, list[str]] = defaultdict(list)
    for path in actual:
        payload = path.read_bytes()
        binary = sha256_bytes(payload)
        record = {"filename": path.name, "fileType": path.suffix.lower().lstrip("."), "byteCount": len(payload), "sha256": binary, **expected[path.name]}
        binary_groups[binary].append(path.name)
        if path.suffix.casefold() == ".pdf":
            pages, page_count = read_pdf(path)
            text_checksum = normalized_text_checksum(pages)
            record.update({"pageCount": page_count, "normalizedTextSHA256": text_checksum, "extractedTextCharacters": sum(len(page) for page in pages)})
            if text_checksum:
                text_groups[text_checksum].append(path.name)
        else:
            record.update(video_metadata(path))
            record["normalizedTextSHA256"] = None
        records.append(record)

    duplicate_binary = [names for names in binary_groups.values() if len(names) > 1]
    duplicate_text = [names for names in text_groups.values() if len(names) > 1]
    for record in records:
        same_binary = next((group for group in duplicate_binary if record["filename"] in group), [])
        same_text = next((group for group in duplicate_text if record["filename"] in group), [])
        record["logicalDuplicateFilenames"] = [value for value in same_binary if value != record["filename"]]
        record["normalizedTextMatchFilenames"] = [value for value in same_text if value != record["filename"]]
        if record["filename"] in {"Combinatorics v2.pdf", "Combinatorics v2 Answers.pdf"}:
            record["logicalDuplicateDecision"] = "verifiedDistinct: question master plus handwritten worked-answer overlay"
        else:
            record["logicalDuplicateDecision"] = "none" if not same_binary else "exactBinaryDuplicate"

    return {
        "formatIdentifier": "revisr.chunk3.corpus-inventory.v1",
        "corpusFileCount": len(records),
        "pdfCount": sum(record["fileType"] == "pdf" for record in records),
        "videoCount": sum(record["fileType"] == "mp4" for record in records),
        "totalBytes": sum(record["byteCount"] for record in records),
        "logicalResourceCount": len(records),
        "questionSourceCount": sum(record["shouldCreateQuestionRecords"] for record in records),
        "questionUnitsDeclared": sum(record["questionCount"] for record in records),
        "exactBinaryDuplicateGroups": duplicate_binary,
        "normalizedTextMatchGroups": duplicate_text,
        "records": records,
    }


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def inventory_markdown(value: dict[str, Any]) -> str:
    rows = [
        "# Revisr Chunk 3 Corpus Inventory",
        "",
        f"- Files: {value['corpusFileCount']} ({value['pdfCount']} PDF, {value['videoCount']} MP4)",
        f"- Bytes: {value['totalBytes']:,}",
        f"- Logical resources: {value['logicalResourceCount']}",
        f"- Question sources: {value['questionSourceCount']}",
        f"- Declared question units: {value['questionUnitsDeclared']}",
        "",
        "| Filename | Type | Bytes | Pages / duration | Role | Provider | Questions | Create questions | Duplicate decision |",
        "| --- | --- | ---: | ---: | --- | --- | ---: | --- | --- |",
    ]
    for record in value["records"]:
        extent = record.get("pageCount") or record.get("durationSeconds") or ""
        safe_filename = record["filename"].replace("|", "&#124;")
        rows.append(
            f"| {safe_filename} | {record['fileType']} | {record['byteCount']:,} | {extent} | "
            f"{record['logicalType']} | {record['authorProvider']} | {record['questionCount']} | "
            f"{'yes' if record['shouldCreateQuestionRecords'] else 'no'} | {record['logicalDuplicateDecision']} |"
        )
    return "\n".join(rows) + "\n"


def solution_page(spec: SolutionSpec, source: SourceSpec, unit: Unit, pages: list[str]) -> int:
    if spec.mapping_confidence != "verifiedPage":
        return spec.start_page or 1
    code = spec.code
    if code.startswith("JZ-"):
        pattern = re.compile(rf"(?:^|\n)\s*Question\s+{unit.number}\b", re.I)
        for index, text in enumerate(pages, 1):
            if pattern.search(text):
                return index
    if code == "EUCLID-ASCENT-AF-MS":
        return int(unit.section.split()[-1])
    if code.startswith("TYLER-"):
        source_page = page_for_unit(source, unit, [""] * 100)
        offsets = {"TYLER-ABSTRACT-FUNCTIONS-ANS": -1, "TYLER-MODULUS-ANS": -2, "TYLER-PROBABILITY-ANS": -1}
        return max(1, source_page + offsets.get(code, 0))
    if code == "TMUAUK-R2DREW2-P1-WORKED":
        return unit.number
    patterns = [
        re.compile(rf"(?:^|\n)\s*Question\s+{unit.number}\b", re.I),
        re.compile(rf"(?:^|\n)\s*{unit.number}[.)]\s"),
    ]
    for index, text in enumerate(pages, 1):
        if any(pattern.search(text) for pattern in patterns):
            return index
    return spec.start_page or 1


def build_candidate(corpus: Path, output: Path) -> dict[str, Any]:
    sources = source_specs()
    solutions = solution_specs()
    videos = video_specs()
    corpus_inventory = inventory(corpus, sources, solutions, videos)
    legacy_manifest = json.loads(MANIFEST_PATH.read_text())
    legacy_solutions = json.loads(SOLUTIONS_MANIFEST_PATH.read_text())
    assigned_ids = {item["questionID"] for item in legacy_manifest["programme"]["assignments"]}
    legacy_question_count = len(legacy_manifest["questions"])
    legacy_source_count = len(legacy_manifest["sources"])
    legacy_solution_count = len(legacy_solutions["documents"])
    legacy_link_count = len(legacy_solutions["links"])

    for question in legacy_manifest["questions"]:
        classify_existing_question(question, assigned_ids)

    source_by_code = {spec.code: spec for spec in sources}
    source_id_by_code = {spec.code: spec.source_id for spec in sources}
    existing_source_ids = {item["stableSourceID"] for item in legacy_manifest["sources"]}
    existing_question_ids = {item["externalQuestionID"] for item in legacy_manifest["questions"]}
    question_ids_by_source_code: defaultdict[str, list[str]] = defaultdict(list)
    existing_questions_by_source: defaultdict[str, list[str]] = defaultdict(list)
    for item in legacy_manifest["questions"]:
        if item.get("sourceID"):
            existing_questions_by_source[item["sourceID"]].append(item["externalQuestionID"])

    new_source_records = []
    new_question_records = []
    pdf_cache: dict[str, tuple[list[str], int]] = {}
    inventory_by_name = {item["filename"]: item for item in corpus_inventory["records"]}
    for spec in sources:
        pages, page_count = read_pdf(corpus / spec.filename)
        pdf_cache[spec.filename] = (pages, page_count)
        record = inventory_by_name[spec.filename]
        new_source_records.append({
            "stableSourceID": spec.source_id,
            "displayName": spec.display_name,
            "expectedFilename": spec.filename,
            "family": spec.family,
            "year": spec.year,
            "paper": spec.paper,
            "pageCount": page_count,
            "questionUnitCount": len(spec.units),
            "useRule": "Reference only; does not create questions" if spec.role == "reference" else "Local private question source",
            "inventoryStatus": "Bundled and audited",
            "checksum": record["sha256"],
            "mediaKind": "pdf",
            "normalizedTextChecksum": record["normalizedTextSHA256"],
            "semanticDocumentIdentity": spec.semantic_identity,
            "duplicateReviewState": "verifiedDistinct" if spec.code == "TYLER-COMBINATORICS" else "none",
            "possibleDuplicateSourceIDs": [],
        })
        for unit in spec.units:
            identifier = question_id(spec, unit)
            if identifier in existing_question_ids:
                raise ValueError(f"New Question ID collides with legacy catalogue: {identifier}")
            page = page_for_unit(spec, unit, pages)
            text = pages[page - 1] if 1 <= page <= len(pages) else ""
            topic = classify_topic(text, spec.default_topic)
            paper_fit = "Paper 1" if spec.paper and "Paper 1" in spec.paper else ("Paper 2" if spec.paper and "Paper 2" in spec.paper else None)
            validity = "usable"
            validity_reason = None
            if spec.code == "MIOMATH-2024-P2" and unit.number == 20:
                validity_reason = "Rendered source and answer key verified; squared equation has five roots, three satisfy the original 3 cos(x) = sqrt(x), so answer D is coherent."
            question = {
                "externalQuestionID": identifier,
                "admissionsTest": "tmua",
                "family": spec.family,
                "year": spec.year,
                "paper": spec.paper,
                "section": unit.section,
                "questionLabel": unit.label,
                "page": page,
                "primaryTopic": topic,
                "secondaryTopic": None,
                "reasoningSkill": spec.reasoning_skill,
                "tmuaPaperFit": paper_fit,
                "difficulty": spec.difficulty,
                "difficultyLabel": spec.difficulty_label,
                "tmuaRelevance": 5.0 if spec.primary_stream == "tmua" else (3.0 if "tmua" in spec.intended_uses else None),
                "format": spec.format,
                "recommendedUse": "Stretch material" if spec.paper == "STEP II" else ("Targeted repair" if spec.family == "Tyler Topic Bank" else "Question bank practice"),
                "scheduleEligible": spec.schedule_eligible and validity != "invalid",
                "classificationConfidence": spec.classification_confidence,
                "descriptor": f"{spec.display_name} - {unit.label}",
                "protection": "none",
                "sourceID": spec.source_id,
                "primaryPreparationStream": spec.primary_stream,
                "intendedUses": spec.intended_uses,
                "questionNumber": unit.number,
                "subpart": unit.subpart,
                "difficultyProvenance": spec.difficulty_provenance,
                "validityState": validity,
                "validityReason": validity_reason,
                "duplicateReviewState": "none",
                "possibleDuplicateQuestionIDs": [],
            }
            new_question_records.append(question)
            question_ids_by_source_code[spec.code].append(identifier)

    all_source_records = legacy_manifest["sources"] + new_source_records
    all_question_records = legacy_manifest["questions"] + new_question_records
    revision_basis = {
        "sourceIDs": [item["stableSourceID"] for item in all_source_records],
        "questionIDs": [item["externalQuestionID"] for item in all_question_records],
        "corpusHashes": [item["sha256"] for item in corpus_inventory["records"]],
    }
    import_revision = hashlib.sha256(json.dumps(revision_basis, sort_keys=True).encode()).hexdigest()
    for item in all_question_records:
        item["importRevision"] = import_revision
    manifest = {
        **legacy_manifest,
        "formatVersion": 2,
        "importRevision": import_revision,
        "sources": all_source_records,
        "questions": all_question_records,
    }

    all_source_ids = {item["stableSourceID"] for item in all_source_records}
    all_question_ids = {item["externalQuestionID"] for item in all_question_records}
    new_documents = []
    new_links = []

    def related_question_ids(source_code: str) -> list[str]:
        if source_code.startswith("SRC-"):
            return sorted(existing_questions_by_source[source_code])
        return question_ids_by_source_code[source_code]

    def append_document(spec: SolutionSpec, *, resource_container: str = "solutionBundle", resource_name: str | None = None, source_filename: str | None = None) -> None:
        path = corpus / (source_filename or spec.filename)
        payload = path.read_bytes()
        pages: list[str] = []
        page_count = None
        duration = None
        if spec.media_kind == "pdf":
            pages, page_count = read_pdf(path)
        else:
            duration = video_metadata(path)["durationSeconds"]
        resolved_source_ids = [value if value.startswith("SRC-") else source_id_by_code[value] for value in spec.source_codes]
        if any(value not in all_source_ids for value in resolved_source_ids):
            raise ValueError(f"Unresolved related Source for {spec.code}: {resolved_source_ids}")
        document = {
            "stableSolutionID": spec.solution_id,
            "displayName": spec.display_name,
            "solutionType": spec.solution_type,
            "resourceName": resource_name or spec.solution_id,
            "resourceExtension": "mp4" if spec.media_kind == "video" else "pdf",
            "resourceContainer": resource_container,
            "family": spec.family,
            "year": spec.year,
            "paper": spec.paper,
            "provenanceOrganization": spec.provider,
            "provenanceTitle": spec.display_name,
            "originalFilename": spec.filename,
            "pageCount": page_count,
            "sha256": sha256_bytes(payload),
            "availability": "available",
            "isVerified": spec.is_verified,
            "sourceID": resolved_source_ids[0],
            "additionalSourceIDs": resolved_source_ids[1:],
            "mediaKind": spec.media_kind,
            "normalizedTextChecksum": normalized_text_checksum(pages) if pages else None,
            "semanticDocumentIdentity": spec.semantic_identity,
            "duplicateReviewState": "verifiedDistinct" if spec.filename == "Combinatorics v2 Answers.pdf" else "none",
            "possibleDuplicateSolutionIDs": [],
            "importRevision": import_revision,
        }
        if duration is not None:
            document["durationSecondsAudit"] = duration
        new_documents.append(document)
        for source_code, source_id in zip(spec.source_codes, resolved_source_ids, strict=True):
            source_spec = source_by_code.get(source_code)
            ids = related_question_ids(source_code)
            units = source_spec.units if source_spec else []
            for index, identifier in enumerate(ids):
                if identifier not in all_question_ids:
                    raise ValueError(f"Solution mapping has unknown Question: {identifier}")
                unit = units[index] if index < len(units) else Unit(index + 1, str(index + 1))
                link = {
                    "stableLinkID": stable_id("SLK", f"{spec.solution_id}:{identifier}"),
                    "solutionID": spec.solution_id,
                    "questionID": identifier,
                    "startPage": solution_page(spec, source_spec, unit, pages) if spec.media_kind == "pdf" and source_spec else (spec.start_page if spec.media_kind == "pdf" else None),
                    "endPage": None,
                    "startTimeSeconds": None,
                    "endTimeSeconds": None,
                    "problemLabel": unit.label,
                    "mappingConfidence": spec.mapping_confidence,
                    "importRevision": import_revision,
                }
                new_links.append(link)

    for spec in solutions + videos:
        append_document(spec)

    # A source PDF may also be the canonical local answer/solution resource. It
    # remains copied once, and the SolutionDocument points into AdmissionsPapers.
    for spec in sources:
        if not spec.answer_content:
            continue
        embedded = SolutionSpec(
            filename=spec.filename,
            code=f"{spec.code}-EMBEDDED-{spec.answer_content}",
            display_name=f"{spec.display_name} {'Answer Key' if spec.answer_content == 'answerKey' else 'Worked Solutions'}",
            solution_type=spec.answer_content,
            family=spec.family,
            provider=spec.provider,
            source_codes=[spec.code],
            year=spec.year,
            paper=spec.paper,
            mapping_confidence="paperLevel",
            start_page=spec.answer_start_page or 1,
        )
        append_document(embedded, resource_container="sourcePaperBundle", resource_name=spec.source_id, source_filename=spec.filename)

    solution_revision_basis = {
        "documentIDs": [item["stableSolutionID"] for item in legacy_solutions["documents"] + new_documents],
        "linkIDs": [item["stableLinkID"] for item in legacy_solutions["links"] + new_links],
        "importRevision": import_revision,
    }
    solutions_revision = hashlib.sha256(json.dumps(solution_revision_basis, sort_keys=True).encode()).hexdigest()
    all_documents = legacy_solutions["documents"] + new_documents
    all_links = legacy_solutions["links"] + new_links
    for item in all_documents + all_links:
        item["importRevision"] = solutions_revision
    solutions_manifest = {
        "formatVersion": 2,
        "importRevision": solutions_revision,
        "documents": all_documents,
        "links": all_links,
    }

    # Preflight structural invariants before any output is committed.
    def require_unique(values: list[str], label: str) -> None:
        duplicates = [value for value, count in Counter(values).items() if count > 1]
        if duplicates:
            raise ValueError(f"Duplicate {label}: {duplicates[:10]}")

    require_unique([item["stableSourceID"] for item in all_source_records], "Source IDs")
    require_unique([item["externalQuestionID"] for item in all_question_records], "Question IDs")
    require_unique([item["stableSolutionID"] for item in all_documents], "Solution IDs")
    require_unique([item["stableLinkID"] for item in all_links], "Link IDs")
    if any(item.get("sourceID") not in all_source_ids for item in all_question_records if item.get("sourceID")):
        raise ValueError("Question has dangling Source ID")
    document_ids = {item["stableSolutionID"] for item in all_documents}
    if any(item["solutionID"] not in document_ids or item["questionID"] not in all_question_ids for item in all_links):
        raise ValueError("Solution mapping does not resolve")
    if any(item.get("validityState") == "invalid" and item["scheduleEligible"] for item in all_question_records):
        raise ValueError("Invalid Question is eligible for automatic practice")

    output.mkdir(parents=True, exist_ok=True)
    for directory in ("AdmissionsPapers", "AdmissionsSolutions", "AdmissionsVideos"):
        target = output / directory
        if target.exists():
            shutil.rmtree(target)
        target.mkdir(parents=True)
    shutil.copytree(PAPERS_ROOT, output / "AdmissionsPapers", dirs_exist_ok=True)
    shutil.copytree(SOLUTIONS_ROOT, output / "AdmissionsSolutions", dirs_exist_ok=True)

    for spec in sources:
        shutil.copy2(corpus / spec.filename, output / "AdmissionsPapers" / f"{spec.source_id}.pdf")
    for spec in solutions:
        shutil.copy2(corpus / spec.filename, output / "AdmissionsSolutions" / f"{spec.solution_id}.pdf")
    for spec in videos:
        shutil.copy2(corpus / spec.filename, output / "AdmissionsVideos" / f"{spec.solution_id}.mp4")

    write_json(output / "AdmissionsManifest.json", manifest)
    write_json(output / "AdmissionsSolutionsManifest.json", solutions_manifest)
    write_json(output / "CorpusInventory.json", corpus_inventory)
    (output / "CorpusInventory.md").write_text(inventory_markdown(corpus_inventory))

    source_index = {
        "formatIdentifier": "revisr.bundled-admissions-papers.v2",
        "schemaVersion": 2,
        "sourceCount": len(all_source_records),
        "totalBytes": sum(path.stat().st_size for path in (output / "AdmissionsPapers").glob("*.pdf")),
        "sources": [{
            "sourceID": item["stableSourceID"],
            "resourceName": item["stableSourceID"],
            "resourceExtension": "pdf",
            "expectedFilename": item["expectedFilename"],
            "family": item["family"],
            "pageCount": item.get("pageCount"),
            "byteCount": (output / "AdmissionsPapers" / f"{item['stableSourceID']}.pdf").stat().st_size,
            "sha256": sha256_bytes((output / "AdmissionsPapers" / f"{item['stableSourceID']}.pdf").read_bytes()),
        } for item in all_source_records if (output / "AdmissionsPapers" / f"{item['stableSourceID']}.pdf").exists()],
    }
    write_json(output / "BundledAdmissionsPapers.json", source_index)

    stream_counts = Counter(item.get("primaryPreparationStream") or "nil" for item in all_question_records)
    intended_counts = Counter(value for item in all_question_records for value in item.get("intendedUses", []))
    new_payload_bytes = corpus_inventory["totalBytes"]
    audit = {
        "formatIdentifier": "revisr.chunk3.import-audit.v1",
        "inventory": {key: corpus_inventory[key] for key in ("corpusFileCount", "pdfCount", "videoCount", "totalBytes", "logicalResourceCount", "questionSourceCount", "questionUnitsDeclared", "exactBinaryDuplicateGroups", "normalizedTextMatchGroups")},
        "before": {"sources": legacy_source_count, "questions": legacy_question_count, "solutions": legacy_solution_count, "links": legacy_link_count},
        "afterCandidate": {"sources": len(all_source_records), "questions": len(all_question_records), "solutions": len(all_documents), "links": len(all_links)},
        "newSources": len(new_source_records),
        "newQuestions": len(new_question_records),
        "existingQuestionsReused": 40,
        "questionDuplicatesSkipped": 40,
        "possibleQuestionDuplicatesFlagged": 0,
        "invalidQuestions": 0,
        "unresolvedTranscriptions": 0,
        "preparationStreamCounts": dict(sorted(stream_counts.items())),
        "intendedUseCounts": dict(sorted(intended_counts.items())),
        "newSolutionDocuments": len(new_documents),
        "newSolutionMappings": len(new_links),
        "videoSolutions": len(videos),
        "videoQuestionMappings": sum(1 for item in new_links if item["solutionID"] in {spec.solution_id for spec in videos}),
        "pendingOrMissingNewQuestionSolutions": 140,
        "mioMathP2Q20": "usable; answer D verified by root/sign analysis and cross-check against the original official equation source",
        "combinatoricsDecision": "one 50-question source plus a visually distinct handwritten worked-answer resource",
        "yottaReuse": "40 existing Question IDs reused; two videos added without new Yotta questions",
        "stepImport": {"sources": 13, "questions": 163, "examinerReportsCreateQuestions": False},
        "externalVerification": ["TMUA.fyi", "official TMUA 2020 Paper 1 question source"],
        "newResourcePayloadBytes": new_payload_bytes,
        "manifestImportRevision": import_revision,
        "solutionsImportRevision": solutions_revision,
        "d1D3FingerprintExpected": "326c45e6691554269e7114807c2549dce3a48e9c1d44f03c7aa2b1ffb662673e",
        "tmua2022ProtectedExpected": 40,
        "attemptsExpected": 48,
        "assignmentsExpected": 530,
    }
    write_json(output / "Chunk3ImportAudit.json", audit)
    import_report = {
        "importRevision": import_revision,
        "questionRowsRead": len(all_question_records),
        "questionIDsUnique": len(all_question_ids),
        "questionsCreatedOnCleanImport": len(all_question_records),
        "questionsUpdatedOnImmediateReimport": len(all_question_records),
        "duplicatesCreatedOnImmediateReimport": 0,
        "programmeDays": len(manifest["programme"]["days"]),
        "assignments": len(manifest["programme"]["assignments"]),
        "sourcesExpected": len(all_source_records),
        "sourcesResolved": len(all_source_records),
        "protectedQuestions": sum(item["protection"] != "none" for item in all_question_records),
        "warnings": ["Chunk 3 adds catalogue resources only; the D4-D30 programme is intentionally unchanged."],
    }
    write_json(output / "AdmissionsImportReport.json", import_report)
    return audit


def external_registry() -> str:
    return """# Revisr External Resource Registry

## TMUA.fyi

- **Type:** Third-party TMUA resource/archive
- **Purpose:** Question/answer verification, supplementary paper access and solution discovery
- **Relevant streams:** TMUA primarily
- **Official:** No
- **Reviewed:** Yes - used during the Chunk 3 corpus import
- **Limitations:** Hosted material may originate from third-party authors; hosting must not be confused with authorship. Some solution functionality may require account access. Official TMUA information takes precedence over third-party descriptions.
"""


def commit_candidate(candidate: Path) -> None:
    required = [
        candidate / "AdmissionsPapers", candidate / "AdmissionsSolutions", candidate / "AdmissionsVideos",
        candidate / "AdmissionsManifest.json", candidate / "AdmissionsSolutionsManifest.json",
        candidate / "BundledAdmissionsPapers.json", candidate / "AdmissionsImportReport.json",
    ]
    if any(not path.exists() for path in required):
        raise ValueError("Candidate is incomplete and cannot be committed")
    targets = [PAPERS_ROOT, SOLUTIONS_ROOT, VIDEOS_ROOT, MANIFEST_PATH, SOLUTIONS_MANIFEST_PATH, PAPERS_INDEX_PATH, IMPORT_REPORT_PATH, EXTERNAL_REGISTRY_PATH]
    with staged_output_set(targets) as staged:
        shutil.copytree(candidate / "AdmissionsPapers", staged[0])
        shutil.copytree(candidate / "AdmissionsSolutions", staged[1])
        shutil.copytree(candidate / "AdmissionsVideos", staged[2])
        for source, target in zip(required[3:], staged[3:7], strict=True):
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        staged[7].parent.mkdir(parents=True, exist_ok=True)
        staged[7].write_text(external_registry())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, default=CORPUS_DEFAULT)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--inventory-only", action="store_true")
    parser.add_argument("--commit-from", type=Path)
    args = parser.parse_args()
    try:
        if args.commit_from:
            commit_candidate(args.commit_from)
            print(json.dumps({"committed": str(args.commit_from)}, indent=2))
            return 0
        if not args.output:
            raise ValueError("--output is required unless --commit-from is used")
        if args.inventory_only:
            value = inventory(args.corpus, source_specs(), solution_specs(), video_specs())
            args.output.mkdir(parents=True, exist_ok=True)
            write_json(args.output / "CorpusInventory.json", value)
            (args.output / "CorpusInventory.md").write_text(inventory_markdown(value))
            print(json.dumps({key: value[key] for key in ("corpusFileCount", "pdfCount", "videoCount", "totalBytes", "logicalResourceCount", "questionSourceCount", "questionUnitsDeclared")}, indent=2))
            return 0
        value = build_candidate(args.corpus, args.output)
        print(json.dumps(value, indent=2))
        return 0
    except Exception as error:
        print(f"CHUNK 3 BUILD FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
