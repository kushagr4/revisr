# Revisr post-recovery validation

Updated 11 October 2026. The first section records the pre-restart diagnostic snapshot. The post-restart verification at the end supersedes its recommendation to restart macOS. Simulator runtime verification and concrete Xcode destination discovery still fail, so no builds, tests, simulator boot, or application walkthrough were performed.

## Repository state

- Repository: `/Users/kushagra/Documents/revisr`
- Branch: `codex/public-foundation-recovered`
- HEAD: `8002a6f53dd5a0423fd9bdb2a10df0d812010b0f`
- `main`: `ae50956356403e1cdc66db117f0f37f693fa5070`
- At report time, the only working-tree item was the pre-existing untracked `revisr.xcodeproj/project.xcworkspace/contents.xcworkspacedata`.
- No application source, signing, simulator data, runtime, or recovery-backup files were changed.

## Host and Xcode

- macOS 26.6.2, build 25G83 (`sw_vers`).
- Xcode 26.6, build 17F113 (`xcodebuild -version`).
- Selected developer directory: `/Applications/Xcode.app/Contents/Developer`.
- Available iOS Simulator SDK: 26.5; iOS SDK: 26.5.
- Disk availability observed in the prior diagnostic: 34 GiB.
- A full macOS restart did not occur between the prior and current diagnostic snapshots. The `launchd` process uptime increased from about 1 day 48 minutes to 1 day 2 hours 4 minutes. Earlier recovery notes document a Simulator-app relaunch, not a host restart.

## Runtime registration, mounting, and verification

`xcrun simctl list runtimes` lists:

- iOS 26.2, build 23C54, runtime ID `com.apple.CoreSimulator.SimRuntime.iOS-26-2`.
- iOS 26.5, build 23F77, runtime ID `com.apple.CoreSimulator.SimRuntime.iOS-26-5`.

`xcrun simctl runtime list -v` reports both disk images as `Ready`, `Signature State: Verified`, and automatically mounted. They are mounted read-only as sealed APFS volumes at `/Library/Developer/CoreSimulator/Volumes/iOS_23C54` and `/Library/Developer/CoreSimulator/Volumes/iOS_23F77`. `hdiutil info` and `mount` confirm both mounts. The images are approximately 7.8 GiB and 7.9 GiB.

The runtime command help was checked before using its verification operation. Fresh verification failed for both runtime image IDs:

```text
xcrun simctl runtime verify FE66F439-12BA-45BA-8D3B-FECC84FCCD02
Signature verification failed: (-67054 a sealed resource is missing or invalid

xcrun simctl runtime verify 2A216799-1479-41A8-A3A0-3096AB18538B
Signature verification failed: (-67054 a sealed resource is missing or invalid
```

The `simdiskimaged` unified log records `SecStaticCodeCheckValidity` failures with `-67054` against each mounted `.simruntime` bundle. The runtime-list `Verified` state therefore conflicts with fresh signature verification. Registration and mounting appear present; runtime integrity verification does not pass.

`simctl runtime match list -v` reports no preferred build map and no user overrides. Its iOS SDK entry is 26.5.1, build 23F81a, and its default/chosen build is 23F81a, while the installed iOS 26.5 runtime is build 23F77. The output does not explicitly declare incompatibility. This build-map difference is worth including in an Apple report, but it does not explain the observed signature error by itself.

## Service and destination health

`xcrun simctl list devices` successfully enumerated available devices under iOS 26.2 and 26.5; every listed device was shut down. After the earlier service PIDs exited, launchd started replacement CoreSimulatorService and `simdiskimaged` processes. No controlled termination was completed in this diagnostic. Runtime listing and verification reached `simdiskimaged`, but Xcode destination discovery remained unhealthy.

`xcodebuild -showdestinations -project revisr.xcodeproj -scheme revisr` exited with code 0 but listed only generic “Any iOS Device” and “Any iOS Simulator Device” destinations. Its logs reported `CoreSimulatorService connection became invalid`, `Connection refused`, no discoverable simulator runtimes, and simulator support disabled. This is not a successful concrete-destination check.

The scoped unified logs show failed XPC connections and the signature-verification failures. `simdiskimaged` also logs absent Mobile Asset directories for tvOS, watchOS, and xrOS; only iOS simulator runtimes are installed here, and the logs do not link those absent directories to the iOS errors. No source-specific Revisr compilation error was produced because no build was run.

## Assessment and next action

The failure is system-wide and remains environmental. Both iOS runtimes are registered and mounted, but fresh verification reports a missing or invalid sealed resource for both. CoreSimulator/Xcode XPC communication also remains intermittent. There is not enough local evidence to distinguish damaged runtime assets from a shared macOS signature-verification or simulator-service problem. Xcode 26.6 contains the iOS 26.5 SDK and the matching minor-version runtime is registered; no explicit compatibility rejection was emitted.

The safest next action is a **manual normal macOS restart**, after saving other work. No host restart is evidenced since the prior diagnostics. This will reinitialize launchd, XPC services, and runtime mounts without deleting simulator data or changing signed files. After restart, repeat runtime verification and concrete destination discovery once.

If either runtime still fails with `-67054`, prepare a sanitized diagnostic package for Apple Developer Support or Feedback Assistant. Do not delete/reinstall runtimes, alter `images.plist`, change security protections, or modify simulator device data without a separate approved repair plan. If Apple or a later investigation recommends repairing an Xcode Components runtime, iOS 26.5 would be the most relevant first candidate because it is the runtime corresponding to this Xcode's iOS 26.5 SDK; its multi-gigabyte replacement could interrupt simulators, so preserve simulator data and obtain approval before proceeding.

## Validation status

| Area | Status |
|---|---|
| Stage A environment diagnosis | Completed; simulator environment remains unhealthy |
| Fresh iOS Simulator Debug/Release builds | Not run; no concrete simulator destination |
| Automated test suite | Not run; no simulator destination |
| Historical migration tests | Unresolved; original fixtures remain unavailable |
| Phase 1–3 functional verification | Not run in this pass |
| Phase 4 visual/accessibility/performance validation | Not run; simulator remains unavailable |
| Recommendation | **Still blocked by simulator environment**; perform a manual macOS restart, then re-verify once |

## Post-restart verification

The user confirmed a full Mac restart before this verification. The restart did not restore simulator operation. Checks below were run on 11 October 2026 around 16:34–16:35 UTC. No process was terminated, and no simulator, runtime, project source, signing configuration, recovery file, or device data was changed.

### Repository checkpoint

- Branch remains `codex/public-foundation-recovered` at `8002a6f53dd5a0423fd9bdb2a10df0d812010b0f`.
- `main` remains `ae50956356403e1cdc66db117f0f37f693fa5070`.
- The working tree has no tracked modifications. The untracked validation report and pre-existing `revisr.xcodeproj/project.xcworkspace/contents.xcworkspacedata` remain present.

### Fresh environment checks

- Host remains macOS 26.6.2 (25G83), using Xcode 26.6 (17F113) at `/Applications/Xcode.app/Contents/Developer`; 34 GiB was available on `/`.
- `xcrun simctl list runtimes` lists iOS 26.2 (23C54) and iOS 26.5 (23F77). `xcrun simctl runtime list -v` reports both mounted and `Ready` with `Signature State: Verified`. That status is contradicted by the explicit fresh checks below.
- `xcrun simctl runtime verify FE66F439-12BA-45BA-8D3B-FECC84FCCD02` exited 1 after about 36 seconds: `Signature verification failed: (-67054 a sealed resource is missing or invalid`.
- `xcrun simctl runtime verify 2A216799-1479-41A8-A3A0-3096AB18538B` exited 1: the same `-67054` sealed-resource error.
- The focused unified log records `SecStaticCodeCheckValidity` failures with `-67054` for both mounted runtime bundles. The runtime images are registered and mounted, but their fresh signature verification does not pass.
- `simdiskimaged` is present in the system launchd domain as PID 1413, with its expected Apple CoreSimulator executable path and `state = running`, `initialized = 1`. Its logs show the signature failures. However, clients cannot use its XPC endpoint reliably: `simctl` reports that it cannot kickstart/connect to `simdiskimaged` and receives an aborted connection through CoreSimulatorService. Service presence therefore does not mean service health is good.
- `ps` process inspection was denied by the sandbox. A read-only launchd query confirmed the `simdiskimaged` job; the guessed CoreSimulatorService launchd labels were not found in the queried domains, so its process state could not be independently established by that query. Client-side XPC evidence is conclusive that CoreSimulatorService is unavailable to these tools.
- `xcrun simctl list devices` exited 1. It reported `CoreSimulatorService connection became invalid`, `Connection refused`, no discoverable simulator runtimes, and `simdiskimaged` not responding. No device list could be obtained, so no boot attempt was made.
- `xcodebuild -showdestinations -project revisr.xcodeproj -scheme revisr` exited 0 but listed only “Any iOS Device” and “Any iOS Simulator Device.” It emitted CoreSimulatorService connection-invalid/refused errors and disabled simulator device support. No concrete usable simulator destination was discovered.
- `xcodebuild` also emitted local cache-directory I/O and provisioning-profile parsing warnings. The latter were not used as a reason to alter signing; they do not account for the runtime signature failures or absent simulator destinations.

### Sanitized Apple support summary

**Title:** Xcode 26.6 cannot discover iOS Simulator devices; both registered runtimes fail fresh sealed-resource verification after macOS restart.

**Environment:** macOS 26.6.2 (25G83), Xcode 26.6 (17F113), selected developer directory `/Applications/Xcode.app/Contents/Developer`, 34 GiB free. Installed iOS simulator runtimes are 26.2 build 23C54 and 26.5 build 23F77. A full host restart was performed before reproducing.

**Reproduction and result:** `xcrun simctl runtime verify` on each registered image UUID returns `-67054: a sealed resource is missing or invalid`. Unified logs show `SecStaticCodeCheckValidity` returning `-67054` for both mounted runtime bundles. `xcrun simctl list devices` fails with CoreSimulatorService connection invalid/refused and reports that `simdiskimaged` is unavailable. `xcodebuild -showdestinations -project revisr.xcodeproj -scheme revisr` exits 0 but provides only generic placeholders and disables simulator support. The launchd job for `simdiskimaged` is running (PID 1413), despite client connection errors.

**Scope and impact:** The failure prevents simulator destination discovery and testing. No simulator device data was reset; no runtime was changed or removed. No application build or test was attempted after these failures. Prior investigation found the same service failure on another Xcode project, consistent with a host-level simulator issue rather than Revisr-specific configuration.

**Question for support:** What supported diagnostic or repair addresses simultaneous `-67054` sealed-resource verification failures for registered iOS simulator runtimes together with CoreSimulatorService/simdiskimaged XPC connection failures on this macOS/Xcode combination? Please advise whether the runtime build-map difference (installed iOS 26.5 runtime 23F77 versus Xcode's iPhoneOS 26.5.1 SDK build 23F81a) is expected or relevant. No compatibility rejection was emitted locally.

This summary omits user data, project source, device identifiers other than the two runtime image UUIDs, and unrelated personal logs. Attach the focused unified-log interval and exact command output when submitting to Apple. Do not attach the full home-directory logs or provisioning profile contents.

### Current validation status

| Area | Status |
|---|---|
| Post-restart runtime verification | **Blocked**; both runtimes fail fresh signature verification with `-67054` |
| CoreSimulatorService / `simdiskimaged` | **Unusable to clients**; `simdiskimaged` launchd job runs, but XPC requests fail |
| Concrete simulator destinations | **Unavailable**; Xcode reports generic placeholders only |
| Existing simulator boot | Not attempted; service and runtime gate failed before boot |
| Fresh Debug/Release simulator builds | Not run; no usable destination |
| Automated tests and clean-user walkthrough | Not run; no usable destination |
| Historical migration tests | Unresolved; original fixtures remain unavailable |
| Phase 1–3 functional verification | Not run in this pass |
| Phase 4 visual/accessibility/performance validation | Not run |
| Phase 4 readiness | **Blocked** pending supported simulator repair and fresh verification |

**Recommended next action:** Submit the sanitized summary and focused logs to Apple Developer Support or Feedback Assistant for supported guidance. Do not alter, delete, reinstall, or re-register either runtime until an approved repair plan is available. No further local recovery action is recommended from these diagnostics alone.
