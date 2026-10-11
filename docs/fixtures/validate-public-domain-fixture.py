#!/usr/bin/env python3
"""Check fixture version and required deterministic parity case structure."""

import json
from pathlib import Path

fixture_path = Path(__file__).with_name("public-diagnostic-planner-parity.v1.json")
fixture = json.loads(fixture_path.read_text(encoding="utf-8"))

assert fixture["schema"] == "revisr-public-diagnostic-planner-parity"
assert fixture["schemaVersion"] == 1
assert fixture["fixtureVersion"] == 1
assert fixture["planning"]["calendar"] == {
    "identifier": "gregorian",
    "timeZone": "UTC",
    "dateConvention": "ISO-8601 civil dates; exam date is exclusive",
}
assert set(fixture["diagnostics"]) >= {
    "tmuaTwoPaperDifficulty", "smcScoring", "bmoSelfAssessment", "tmuaLowEvidence"
}
assert set(fixture["planning"]) >= {
    "input", "expected", "zeroAvailableDays", "shortPreparationWindow", "diagnosticQuestionEligibility"
}
assert fixture["planning"]["zeroAvailableDays"]["expectedError"] == "noAvailableDays"
assert fixture["planning"]["shortPreparationWindow"]["expected"]["availableStudyDays"] == 1
assert fixture["planning"]["diagnosticQuestionEligibility"]["expected"]["assignedQuestionIDs"] == [
    "diagnostic-wrong"
]
assert fixture["planning"]["diagnosticQuestionEligibility"]["expected"]["excludedQuestionIDs"] == [
    "diagnostic-unassessed"
]
assert fixture["planning"]["expected"]["unfilledDays"] == 0
assert fixture["diagnostics"]["tmuaLowEvidence"]["expected"]["topicEvidence"] == "insufficient"

print(f"Fixture structure/version valid: {fixture_path}")
