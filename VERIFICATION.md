# Publication verification — Tablet Studio 1.1.4

Date: **16 November 2026**. Hardware target: **Wacom Intuos Pro Small PTH-451** (`0x056a:0x0314`).

## What this record establishes

This is a bounded, direct pre-publication review, not a certification, independent security audit or guarantee of zero bugs. The owner reports that the existing software works well. No runtime application/driver source was changed during this preparation. The existing Mac downloads were preserved; documentation, download checksums, a Git ignore file and additional reproducible regression checks were added.

The check host reported macOS **27.2.1 (26B131)**, Apple silicon (`arm64`), Apple Swift **6.4.2**, and Python 3. The original apps declare macOS **13.0** minimum, version **1.1.4**, build **8**. Declared targets do not establish runtime support on all those systems.

## Results

| Check | Actual result | Boundary |
| --- | --- | --- |
| Original transfer-kit manifest | All listed files matched their recorded SHA-256 checksums. | Integrity, not publisher authentication or malware certification. |
| Original source preservation | All 28 archived source/build/test/license files matched the extracted publication copies byte-for-byte. | Added release probes are separate files, not changes to the existing driver. |
| Existing regression runner: `bash Checks/run.sh` | Exit 0. Sixteen upstream/Resolve/palm-rejection checks and the bundled settings, pen, drag, touch, raw-packet, repeated-gesture and keyboard-event check groups passed. | Synthetic/captured packet inputs; touch output is recorded by a test double, and keyboard events are constructed without posting them. |
| Additional pressure matrix | Exit 0. 10,240 pressure samples across exponents 0.25, 0.5, 1, 2 and 3 passed bounds, monotonicity, soft/firm direction and linear-identity assertions; clamping, persistence, invalid exponent rejection and supplied JSON import also passed. | Exercises the actual settings/curve implementation, not pressure on a physical tablet or a drawing application's brush. |
| Additional parser robustness | Exit 0 under AddressSanitizer. 64,000 deterministic buffers of lengths 0–127 were passed through stateful touch decoding and pen decoding with report IDs 2, 3 and 192. Output invariants passed; no sanitizer error was reported. | A bounded generated-input probe, not exhaustive protocol validation or complete driver memory-safety proof. |
| Consolidated runner: `bash Checks/release.sh` | Exit 0 for existing checks and both added probe groups on the final source/test tree. | Does not install/start a driver or post desktop input. |
| Fresh packaging build: `python3 packaging/studio.py <fresh-output-directory>` | Exit 0; produced the app, ZIP and `.pkg`. Both executable architectures were `x86_64 arm64`; version 1.1.4. Strict/deep code-signature verification passed for the rebuilt app and helper. | Build/package evidence, not an installed-device test. Rebuilt artifacts were not substituted for the existing working downloads. |
| Original downloaded app | ZIP integrity passed. Strict/deep ad-hoc signature verification passed. Original GUI binary contains the pressure-response label. Both original executable files were byte-identical between the supplied PKG payload and ZIP app. | String inspection alone does not validate rendered UI or slider interaction. |
| Supplied Mac download checksums | All entries in this repository's `SHA256SUMS.txt` passed. | Mac downloads only; Windows executable excluded. |
| Secret/exclusion review | No matches for the selected private-key, GitHub-token, AWS access-key, API-key or secret-literal patterns were found in the archived source. Upload selection excludes logs, environment files, personal launch agents, local verification directories, build outputs and Windows installers. | Heuristic and direct review, not a guarantee that every possible secret pattern has been detected. |
| `swift test` | **NOT PASSED / ENVIRONMENT BLOCKED:** the Command Line Tools toolchain could not resolve `XCTest`. | This failure was retained, not relabeled as a successful unit-test run. Use full Xcode for that route. The standalone regressions above completed successfully. |
| Separate specialist review | **NOT PERFORMED:** the approved team router rejected `tablet-studio` because the project is not registered. | No independent-review claim is made and no team-routing settings were altered. |

The build emitted missing developer-framework search-path warnings under Command Line Tools. Packaging still completed successfully. The XCTest dependency failure is listed separately above.

An initial heuristic binary-string check incorrectly required the exact short heading `Pen pressure` to appear as contiguous printable bytes. That assertion failed; it is not a reliable UI oracle for Swift small-string encoding. The existing pressure-response text was found, the actual source contains the control, and curve tests passed. No app change was made to satisfy that heuristic; rendered-UI acceptance remains unperformed.

## Reproduce the safe automated checks

On a Mac with the required toolchain, from the repository root:

```bash
bash Checks/release.sh
shasum -a 256 -c SHA256SUMS.txt
python3 packaging/studio.py ./dist
```

`Checks/Pressure/main.swift` and `Checks/Robustness/main.swift` contain the added assertions. The runner compiles temporary executables and removes its temporary directory on exit. AddressSanitizer must be available in the Apple toolchain for the robustness probe. Build outputs and scratch directories are not source files for publication.

## Not verified in this preparation

- **Fresh physical tablet acceptance:** the read-only USB inventory found no connected Wacom device. Pen pressure in a drawing application, tactile buttons/ring, real gestures, permission prompts and live USB input could not be exercised here.
- **Fresh GUI interaction:** the actual rendered settings window and slider/Apply interaction were not automated. Source wiring, pressure persistence/validation and packaged pressure text were checked instead.
- Installation/start/stop, per-user login startup, failed-install rollback and uninstall were reviewed in source but not executed against a user's live driver setup. The working installed configuration was not changed.
- Another Mac, Intel runtime, all macOS 13+ versions, wireless hardware, extended sleep/wake and reconnect behavior, multiple tablets, multi-monitor use and every receiving application's pressure/eraser support.
- Windows or Linux. This is a macOS app and uses Apple-only frameworks. There is no native Windows build; a port would require implementation and testing, not just a different build command.
- Apple Developer ID signing or notarization. The existing installer has **no signature** and the apps use ad-hoc signatures. Neither is an Apple approval/security assessment.

## Manual acceptance before relying on your setup

1. Confirm **Wacom Intuos Pro PTH-451**, back up existing settings and connect by USB.
2. Install one Mac download, start its helper and grant both required permissions.
3. In a pressure-aware app, compare light/firm strokes and soft/linear/firm curves after Apply.
4. Check pen side-button clicks/hold/release, tip overlap and eraser modes.
5. Check all tablet buttons, four ring modes and your own Resolve keyboard preset.
6. Check taps, scroll, three-finger drag, staggered lift, four-finger switching and pen/palm takeover.
7. Export/import settings; verify persistence and that Apply updates the driver.
8. Test stop/start, logout/login, unplug/replug and sleep/wake. Confirm recovery to your previous driver if needed.

Report a reproducible defect with the exact setup and redacted evidence. Passing the automated scope above does not remove the need for these device-level checks.
