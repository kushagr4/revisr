import collections
import json
import unittest
from datetime import date, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / ".qa" / "chunk4" / "staging-v1"


def load(path: Path):
    return json.loads(path.read_text())


class Chunk4ProgrammeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = load(ROOT / "revisr" / "Resources" / "AdmissionsManifest.json")
        cls.solutions = load(ROOT / "revisr" / "Resources" / "AdmissionsSolutionsManifest.json")
        cls.plan = load(STAGING / "AdmissionsProgrammeMigration.json")
        cls.audit = load(STAGING / "Chunk4ProgrammeAudit.json")
        cls.questions = {q["externalQuestionID"]: q for q in cls.base["questions"]}
        cls.sources = {s["stableSourceID"]: s for s in cls.base["sources"]}

    def test_corpus_is_unchanged_and_all_programme_relationships_resolve(self):
        self.assertEqual(len(self.base["questions"]), 2_600)
        self.assertEqual(len(self.base["sources"]), 136)
        self.assertEqual(len(self.solutions["documents"]), 120)
        self.assertEqual(len(self.solutions["links"]), 2_364)
        ids = [a["externalAssignmentID"] for a in self.plan["assignments"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(a["questionID"] in self.questions for a in self.plan["assignments"]))
        self.assertTrue(all(1 <= a["dayNumber"] <= 30 for a in self.plan["assignments"]))

    def test_d1_d3_assignment_records_are_byte_for_byte_equivalent(self):
        expected = [a for a in self.base["programme"]["assignments"] if a["dayNumber"] <= 3]
        actual = [a for a in self.plan["assignments"] if a["dayNumber"] <= 3]
        self.assertEqual(actual, expected)
        self.assertEqual([len([a for a in actual if a["dayNumber"] == day]) for day in (1, 2, 3)], [16, 16, 15])

    def test_exact_dates_tuesday_restrictions_and_flex_gaps(self):
        expected = {
            4: "2026-08-31", 5: "2026-09-01", 6: "2026-09-02", 7: "2026-09-04",
            8: "2026-09-07", 9: "2026-09-08", 10: "2026-09-09", 11: "2026-09-11",
            12: "2026-09-14", 13: "2026-09-15", 14: "2026-09-16", 15: "2026-09-18",
            16: "2026-09-19", 17: "2026-09-21", 18: "2026-09-22", 19: "2026-09-23",
            20: "2026-09-25", 21: "2026-09-28", 22: "2026-09-29", 23: "2026-09-30",
            24: "2026-10-02", 25: "2026-10-05", 26: "2026-10-06", 27: "2026-10-07",
            28: "2026-10-09", 29: "2026-10-12", 30: "2026-10-14",
        }
        start = date(2026, 8, 22)
        days = {d["dayNumber"]: d for d in self.plan["days"]}
        actual = {n: (start + timedelta(days=days[n]["scheduleOffsetDays"])).isoformat() for n in expected}
        self.assertEqual(actual, expected)
        tuesdays = {5, 9, 13, 18, 22, 26}
        self.assertTrue(all(days[n]["earliestStartMinute"] == 840 for n in tuesdays))
        self.assertTrue(all(days[n]["earliestStartMinute"] is None for n in set(range(1, 31)) - tuesdays))
        scheduled_dates = set(actual.values())
        self.assertTrue(set(self.plan["flexDates"]).isdisjoint(scheduled_dates))
        self.assertTrue(all(date.fromisoformat(value).strftime("%A") not in {"Thursday", "Sunday"} for value in scheduled_dates))

    def test_diagnostics_and_official_benchmarks_use_exact_sources(self):
        by_day = collections.defaultdict(list)
        for assignment in self.plan["assignments"]:
            if assignment["dayNumber"] >= 4:
                by_day[assignment["dayNumber"]].append(self.questions[assignment["questionID"]])
        self.assertEqual({q["sourceID"] for q in by_day[7]}, {"SRC-E29687FAAA262C5F"})
        self.assertEqual({q["sourceID"] for q in by_day[11]}, {"SRC-D475EB66A3CA6BF0"})
        expected = {
            15: {(2017, "Paper 1")}, 16: {(2017, "Paper 2")},
            19: {(2018, "Paper 1")}, 20: {(2018, "Paper 2")},
            21: {(2019, "Paper 1"), (2019, "Paper 2")},
            25: {(2020, "Paper 1")}, 26: {(2020, "Paper 2")},
            28: {(2021, "Paper 1"), (2021, "Paper 2")},
        }
        for day, papers in expected.items():
            self.assertEqual({(q["year"], q["paper"]) for q in by_day[day]}, papers)
            self.assertTrue(all(q["family"] == "TMUA Actual" for q in by_day[day]))
        self.assertFalse(any(q["family"] == "TMUA Actual" and q.get("year") == 2022 for rows in by_day.values() for q in rows))
        protected_2022 = [q for q in self.questions.values() if q["family"] == "TMUA Actual" and q.get("year") == 2022 and q["protection"] != "none"]
        self.assertEqual(len(protected_2022), 40)

    def test_stream_integration_and_workload_are_deliberate(self):
        d4_questions = [self.questions[a["questionID"]] for a in self.plan["assignments"] if a["dayNumber"] >= 4]
        primary = collections.Counter(q.get("primaryPreparationStream") or "nil" for q in d4_questions)
        intended = collections.Counter(stream for q in d4_questions for stream in set(q.get("intendedUses") or []))
        self.assertGreaterEqual(primary["tmua"], 300)
        self.assertGreaterEqual(primary["csat"], 10)
        self.assertGreaterEqual(primary["smc"], 16)
        self.assertGreaterEqual(primary["bmo"], 3)
        self.assertGreaterEqual(intended["cambridgeCSInterview"], 4)
        days = {d["dayNumber"]: d for d in self.plan["days"]}
        counts = collections.Counter(a["dayNumber"] for a in self.plan["assignments"])
        for number in list(range(4, 7)) + [8, 10, 12, 13, 14, 17, 22, 23, 24, 27, 29, 30]:
            self.assertLessEqual(counts[number], 14)
        self.assertEqual(counts[9], 4)
        self.assertEqual(counts[18], 5)
        self.assertTrue(all(days[n]["expectedReviewMinutes"] >= 40 for n in range(4, 31)))
        self.assertEqual(self.audit["finalActiveAssignments"], 452)
        self.assertEqual(self.audit["oldD4PlusDeactivated"], 442)

    def test_only_documented_repair_questions_repeat(self):
        assignments = [a for a in self.plan["assignments"] if a["dayNumber"] >= 4]
        occurrences = collections.defaultdict(list)
        for item in assignments:
            occurrences[item["questionID"]].append(item["dayNumber"])
        repeated = {identifier for identifier, days in occurrences.items() if len(days) > 1}
        allowed = {
            "MAT-2017-Q1F", "TSPEC-P1-Q18", "TYLER-C-P1-Q07", "YOTTA-P1-Q11",
            "YOTTA-P2-Q08", "TYLER-B-P2-Q09", "MAT-2019-Q1D", "MAT-2020-Q1E",
            "TSPEC-P1-Q19", "TPRA-P2-Q03",
        }
        self.assertTrue(repeated.issubset(allowed), repeated - allowed)
        self.assertTrue(all(len(days) == len(set(days)) for days in occurrences.values()))


if __name__ == "__main__":
    unittest.main()
