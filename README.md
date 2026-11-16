# Tablet Studio — Wacom Intuos Pro PTH-451

An open-source, community **macOS driver and settings app specifically for the Wacom Intuos Pro Small PTH-451**.

Tablet Studio provides pen input with adjustable pressure response, configurable pen/tablet buttons, touch-ring shortcuts and finger gestures. This is an independent community project, not an official Wacom driver or a Wacom-endorsed product.

> **Check the model printed underneath your tablet before installing.** This release recognizes **Wacom Intuos Pro PTH-451** only (USB vendor `0x056a`, product `0x0314`). **PTH-460 and other models are not supported.** Similar names do not mean compatible hardware.

## Platform support

| Platform | Status |
| --- | --- |
| macOS on Apple silicon | Developed and built on a Mac. The owner reports the existing software works well on the original Mac; automated checks and a fresh build also passed during publication preparation. Your own hardware/app combination still needs testing. |
| macOS on Intel | The supplied apps include `x86_64` and `arm64` binaries. Intel runtime/hardware operation has not been verified. |
| Windows | **No Tablet Studio Windows application or installer is provided. Windows operation has not been tested.** |
| Linux | Not supported by this release. |

The build target is **macOS 13 or later**. A deployment target is not proof that every macOS version has been tested.

### Note for Windows users

**This software was developed and built using macOS.** The source depends on Apple's SwiftUI, AppKit, CoreGraphics and IOKit frameworks, so it **will not build or run unchanged on Windows**. Installing Swift on Windows alone is not sufficient.

Windows users who want a native version must port the macOS-specific components, build it themselves and test it on their own Windows machine and **Wacom Intuos Pro PTH-451**. Contributions with reproducible build instructions and test evidence are welcome. Until then, use a separately obtained official Wacom Windows driver that explicitly supports your tablet and Windows version, and test it yourself. Mac settings JSON files cannot be imported into Wacom's Windows settings app.

**No Windows driver executable is redistributed in this repository.** Windows references inside the existing Mac app are historical guidance, not a tested Tablet Studio Windows release or a guarantee of current Wacom compatibility.

## Download the Mac app

**[Download for Mac — Tablet Studio v1.1.4](https://github.com/zyteng1997/tablet-studio/releases/tag/v1.1.4)**

Get the ready-to-install app from **GitHub Releases**. The source code stays in this repository; GitHub's automatic “Source code” archives are not installers.

- [Tablet-Studio-Mac.pkg](https://github.com/zyteng1997/tablet-studio/releases/download/v1.1.4/Tablet-Studio-Mac.pkg) — installs `Tablet Studio.app` in `/Applications`.
- [Tablet-Studio-Mac.zip](https://github.com/zyteng1997/tablet-studio/releases/download/v1.1.4/Tablet-Studio-Mac.zip) — alternative containing the same app; extract and copy it to `/Applications`.
- [PTH451-settings.json](https://github.com/zyteng1997/tablet-studio/releases/download/v1.1.4/PTH451-settings.json) — optional settings preset with DaVinci Resolve shortcuts. Review before applying; it replaces the app's current settings rather than merging them.
- [SHA256SUMS.txt](https://github.com/zyteng1997/tablet-studio/releases/download/v1.1.4/SHA256SUMS.txt) — download beside the three release files, then run `shasum -a 256 -c SHA256SUMS.txt` from that folder.

The original copies also remain in the [Mac](Mac) folder. The repository's [SHA256SUMS.txt](SHA256SUMS.txt) uses `Mac/` paths for the clone-based check below; the release checksum file uses filenames without that prefix.

Choose **one** installation method. The downloads preserve the existing working transfer-kit binaries; a fresh source rebuild was checked separately, not substituted silently for them.

To verify downloads after cloning the repository, run from its root:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

Checksums help detect changed or damaged downloads. They do not establish publisher identity, Apple approval or freedom from malware.

## Install and start on macOS

1. Confirm the tablet is **Wacom Intuos Pro PTH-451**, then connect it by USB.
2. Preserve your current tablet-driver settings. Avoid running another tablet driver at the same time; use its normal stop/uninstall controls if it conflicts.
3. Install the `.pkg`, **or** extract the `.zip` and move `Tablet Studio.app` to `/Applications`.
4. Open **Tablet Studio → Setup → Install / Start Driver**. This installs the bundled helper at `~/Applications/Wacom PTH-451 Driver.app` and configures login startup for your user account.
5. In **System Settings → Privacy & Security**, allow **Wacom PTH-451 Driver** in both **Accessibility** and **Input Monitoring**. Setup includes buttons to open these pages. If needed, add the helper from the path above. Complete password/Touch ID prompts yourself.
6. Restart the driver using **Install / Start Driver** after granting the permissions.
7. Optionally use **Setup → Import Settings**, select `PTH451-settings.json`, review all settings, then click **Apply**.
8. Test the pen, pressure, buttons and gestures in the applications you actually use. A running-process indicator does not prove that the tablet is connected or permissions are granted.

### macOS security warning

The installer is **unsigned**. The apps are **ad-hoc signed**, without an Apple Developer ID, and **not Apple-notarized**. You may see an unidentified-developer or verification warning.

Only proceed if you trust this project and the downloaded files. Review [Apple's guidance on safely opening apps](https://support.apple.com/en-us/102445). If you decide to grant an exception, use **System Settings → Privacy & Security → Open Anyway** for the specific blocked file. A separately blocked app may need its own exception. **Do not disable Gatekeeper or other system protections globally.** Approval does not add support for another tablet model.

## Pen pressure settings

Open **Pen & Touch → Pen pressure → Pressure response · soft ← → firm**, adjust the slider and click **Apply**.

- **1.00** — linear response; the default and supplied preset value.
- **Below 1.00** — softer response: lighter physical pressure produces a stronger output.
- **Above 1.00** — firmer response: more physical pressure is needed for the same output.
- Adjustable range: **0.25–3.00**.

The driver normalizes the PTH-451 pressure sample, applies the selected response curve and includes it in the generated tablet/mouse events. Drawing strength depends on the receiving app supporting pressure and on its brush/tool configuration. This release has no live pressure-test graph.

**Quick test:** in a pressure-aware drawing app, enable pressure sensitivity for brush size or opacity. Draw with light and firm pressure, then compare soft, linear and firm settings. Export your settings before experimenting if you want an easy way back.

## Controls and gestures

| Area | Available controls |
| --- | --- |
| Pen | Adjustable pressure curve; lower/upper side buttons can left-click/drag, right-click, middle-click, send a shortcut or be disabled. |
| Eraser | Erase, act as a pen, or be disabled. Actual erasing requires application support for tablet erasers. |
| Tablet buttons | Six configurable keyboard shortcuts. |
| Touch ring | Four modes, two directional shortcuts per mode; press the centre to cycle modes. Adjustable ring travel per shortcut. |
| One finger | Relative cursor movement and optional tap-to-click. |
| Two fingers | Scrolling and optional right-click tap. |
| Three fingers | Select drag, desktop/Mission Control gestures, or off. For window dragging, position the cursor on the title bar first; lift a finger to drop, then lift all fingers before starting again. |
| Four fingers | Desktop/full-screen-app switching or application switching horizontally; Mission Control/app windows vertically while four-finger gestures are enabled. |
| Palm rejection | Optional blocking of finger input while the pen is nearby; lift the pen and palm to resume touch. |

Click **Apply** after changes. Pen input maps to the **primary display**; touch cursor movement is relative. Desktop/Mission Control gestures depend on the corresponding macOS Control-arrow shortcuts being enabled. Horizontal desktop switching needs an adjacent desktop or full-screen app.

The supplied shortcuts target DaVinci Resolve, and keyboard shortcuts/ring actions default to Resolve-only. Match your own Resolve keyboard preset. Pen click and eraser actions apply across apps.

## Stop or remove

1. Export any settings you want to keep.
2. In **Setup**, click **Stop Driver & Login Startup**.
3. To uninstall, move `/Applications/Tablet Studio.app` and `~/Applications/Wacom PTH-451 Driver.app` to Trash. A previous helper may also remain at `~/Applications/Wacom PTH-451 Driver.previous.app`.

Settings are retained at `~/Library/Application Support/wacomd/config.json`; logs are at `~/Library/Logs/WacomPTH451/driver.log`. The app does not provide a full uninstall button.

## Troubleshooting

- **PTH-460 or another model:** do not install this driver for it. Use an appropriate official driver instead.
- **App opens but the pen does nothing:** check the exact model, USB connection, both permissions and competing drivers. Restart the driver after permission changes; inspect the driver log.
- **Pressure appears constant:** use a pressure-aware app with pressure-enabled brush settings, select a different pressure response and click Apply.
- **Touch stops while hovering:** palm rejection deliberately blocks touch while the pen is nearby. Lift the pen and all fingers/palm, wait briefly, then try again.
- **Desktop gestures do nothing:** verify macOS keyboard shortcuts and available adjacent desktops/full-screen apps. Consider application switching instead.
- **Resolve shortcuts do the wrong thing:** change the recorded shortcuts to match your installed Resolve keyboard preset, then Apply.
- **Imported settings fail:** import a Tablet Studio JSON export, not a Wacom Windows configuration. Invalid or out-of-range settings are rejected.

## Build from source on a Mac

Requirements: a macOS host, **Python 3**, and an Apple **Swift 5.9+ toolchain** with the macOS SDK, `codesign`, `pkgbuild` and `ditto`. The Swift manifest declares tools version 5.9; publication checks used the toolchain recorded in [VERIFICATION.md](VERIFICATION.md). Full Xcode is needed for the XCTest route below if your Command Line Tools installation does not include XCTest. There are no third-party Swift package dependencies in the supplied manifest.

```bash
git clone https://github.com/zyteng1997/tablet-studio.git
cd tablet-studio

# Safe automated checks: no driver installation or input events posted.
bash Checks/run.sh

# Extended release checks: pressure matrix and AddressSanitizer parser probes.
bash Checks/release.sh

# Build a universal app (Apple silicon + Intel), ZIP and installer.
python3 packaging/studio.py ./dist
```

Outputs are `dist/Tablet Studio.app`, `dist/Tablet-Studio-Mac.zip` and `dist/Tablet-Studio-Mac.pkg`. The build script also uses a sibling `wacomd-universal` build directory; choose a checkout location where creating that directory is appropriate. Local builds remain ad-hoc signed and not notarized. Building does **not** install or start the driver.

With a full Xcode installation that supplies XCTest, the package's unit tests can also be run with:

```bash
swift test
```

If this reports that the `XCTest` module cannot be resolved under Command Line Tools, use `bash Checks/run.sh` for the bundled standalone regression checks. Do not interpret an unavailable XCTest run as a pass.

### Source layout

- `Sources/WacomdShared` — settings schema, validation, pressure curve and persistence.
- `Sources/wacomd` — HID parsing, pen/touch handling and macOS event generation.
- `Sources/wacomd-config` — SwiftUI settings app and per-user driver setup.
- `Tests/wacomdTests` — XCTest unit tests.
- `Checks` — standalone pen/settings, gesture, raw-packet and keyboard-event regressions.
- `packaging/studio.py` — universal app and installer build.
- `Mac` — existing Mac downloads and optional preset.

## Verification and known limits

See [VERIFICATION.md](VERIFICATION.md) for the actual pre-publication checks and their limits. Passing automated tests is **not** a promise that the software has no bugs.

The owner reports the current software works well on the original Mac. Another Mac, Intel runtime, Windows, wireless operation, extended sleep/wake/reconnection and every drawing/editing application have **not** been validated here. This release is intended for one supported tablet; monitor/area mapping, rotation, per-app profile management, automatic updates/rollback, notarization and full uninstallation are not implemented.

Do not rely on this release for critical work until you have tested your own setup and preserved a recovery route to your previous driver/settings.

## Contributing and reporting issues

Open an issue with your exact tablet model, Mac chip, macOS version, app/build version, USB/wireless connection, affected application, reproduction steps, expected result and actual result. Include only relevant redacted log excerpts; remove usernames, serial numbers and other personal information. Do not post credentials or private documents.

Keep pull requests focused, explain why the change is needed, add a reproducible regression where possible and run `bash Checks/run.sh`. Hardware- or Windows-support claims need actual build/run evidence; a successful compile alone is not enough. No Windows port is currently promised.

## License and attribution

The supplied source is released under the **[MIT License](LICENSE)**. The existing upstream copyright notice for **Yanick Blancho** is preserved. Tablet Studio is based on the supplied `wacomd` code; see source comments for implementation references. Redistribution and modification must retain the required license and copyright notice.

Wacom, Intuos and related names belong to their respective owners and are used only to identify hardware compatibility. This community release is supplied as-is, without warranty.
