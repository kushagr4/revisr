"""Transactional filesystem staging for Revisr generation scripts."""

from __future__ import annotations

import os
import shutil
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator, Sequence


@contextmanager
def staged_output_set(targets: Sequence[Path]) -> Iterator[list[Path]]:
    """Yield isolated paths, then replace all targets only after success.

    Existing targets are moved to private backups during the short commit. If
    any replacement fails, every already-replaced target is restored.
    """

    if not targets:
        raise ValueError("At least one output target is required")
    resolved = [target.resolve() for target in targets]
    staging_parent = next(
        parent
        for parent in [resolved[0].parent, *resolved[0].parents]
        if parent.exists()
    )
    root = Path(tempfile.mkdtemp(prefix=".revisr-generation-", dir=staging_parent))
    staged = [root / "staged" / str(index) for index in range(len(resolved))]
    backups = [root / "backups" / str(index) for index in range(len(resolved))]
    replaced: list[int] = []
    backed_up: list[int] = []
    try:
        yield staged
        missing = [str(target) for target in staged if not target.exists()]
        if missing:
            raise ValueError(f"Generator did not produce every staged output: {missing}")

        for target in resolved:
            target.parent.mkdir(parents=True, exist_ok=True)
        (root / "backups").mkdir(parents=True, exist_ok=True)
        try:
            for index, target in enumerate(resolved):
                if target.exists():
                    os.replace(target, backups[index])
                    backed_up.append(index)
            for index, target in enumerate(resolved):
                os.replace(staged[index], target)
                replaced.append(index)
        except Exception:
            for index in reversed(replaced):
                target = resolved[index]
                if target.is_dir():
                    shutil.rmtree(target)
                elif target.exists():
                    target.unlink()
            for index in reversed(backed_up):
                os.replace(backups[index], resolved[index])
            raise
    finally:
        shutil.rmtree(root, ignore_errors=True)
