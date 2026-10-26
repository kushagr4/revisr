#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
smoke_dir="${TMPDIR:-/tmp}/revisr-production-logic-smoke"
mkdir -p "$smoke_dir/module-cache"

xcrun --sdk macosx swiftc -module-cache-path "$smoke_dir/module-cache" \
  -o "$smoke_dir/production-logic-smoke" \
  "$repo_root/revisr/Models/ModelEnums.swift" \
  "$repo_root/revisr/Models/Admissions/AdmissionsEnums.swift" \
  "$repo_root/revisr/Models/Admissions/PublicPreparation.swift" \
  "$repo_root/revisr/Services/Admissions/PublicPlanningEngine.swift" \
  "$repo_root/revisr/Services/Admissions/DiagnosticAnalysis.swift" \
  "$repo_root/docs/fixtures/production-logic-smoke.swift"

"$smoke_dir/production-logic-smoke"
