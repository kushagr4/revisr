# Revisr resource size audit

Measured 9 October 2026 from the working tree with Python `Path.rglob`, counting regular files and summing byte sizes. This is a source-tree measurement, not an App Store compressed size.

| Resource group | Files | Bytes | Approx. size |
|---|---:|---:|---:|
| Admissions papers | 136 | 47,774,410 | 45.6 MiB |
| Admissions solutions | 98 | 67,677,539 | 64.5 MiB |
| Admissions videos | 8 | 329,716,387 | 314.4 MiB |
| Assets.xcassets | 4 | 816,117 | 0.8 MiB |
| **Measured total** | **246** | **445,984,453** | **425.3 MiB** |

The eight video files are the dominant size contributor at roughly 74% of the measured resource bytes. They remain bundled development resources while Phase 5 verifies provenance, creator attribution and redistribution permission. They must not be deleted silently because solution relationships and private historical behaviour still need to be preserved.

The current public architecture already resolves papers and solutions through local library services, so a future rights-cleared public build can omit unapproved resources at import time without replacing them with unverified network URLs. A follow-up size pass should compare a rights-cleared resource manifest with the built `.app` and measure cold launch and PDF opening on a stable simulator.
