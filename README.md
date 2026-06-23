# Mac-AMD-GPU-BootCamp-Driver-Studio

<img width="1441" height="1076" alt="Image" src="https://github.com/user-attachments/assets/f9c72b55-dbc0-409e-b8f5-3d442fb734c0" />
<img width="1438" height="933" alt="Image" src="https://github.com/user-attachments/assets/c1804f1c-5aabd" />
<img width="1602" height="686" alt="Image" src="https://github.com/user-attachments/assets/423029b9-5e2b-42fa-a1cf-1fe5b6afde38" />

AMD Boot Camp Driver Studio is an unofficial utility that prepares, verifies, patches, locally signs, installs, backs up, and restores a newer AMD Radeon RX 5500M-family driver package for the Radeon Pro 5500M found in the 2019 16-inch MacBook Pro.

This project is currently limited to a specific Boot Camp setup. It is not a universal AMD Boot Camp driver package.

## Current Supported Environment

* MacBook Pro 16-inch, 2019
* AMD Radeon Pro 5500M
* Hardware ID: `PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`
* Windows 10/11 64-bit through Boot Camp
* AMD Software: Adrenalin Edition 26.6.1

Other GPUs, Mac models, and driver packages are not currently supported unless a matching verified profile is explicitly added.

The tool stops before making changes unless the detected hardware ID, package structure, file size, and required SHA-256 hashes match the selected profile.

## Planned / Experimental Support

The following items are planned for a future update and should not be treated as verified support yet:

* Radeon Pro 5300M support and compatibility improvements
* Improved non-binary-patched AMD Adrenalin 26.6.1 workflow for Radeon Pro 5500M / 5300M
* UI structure, readability, and user experience improvements
* Fix for the app freeze that can occur during the backup process after the screen flickers
* Clear success/failure dialogs after driver installation
* A dedicated installation guide to make each installation step easier to understand

The current AMD Adrenalin 26.6.1 profile for the Radeon Pro 5500M requires binary patching to work correctly.

A non-binary-patched 26.6.1 test option may be included for testing purposes, but it is currently not expected to work correctly.

## Project Goal

The goal of this project is to make a reproducible local workflow for preparing a compatible AMD driver package on unsupported Boot Camp hardware.

It is intended to avoid repeated manual file editing by making the process explicit, profile-based, hash-checked, locally signed, and recoverable.

The project does not redistribute AMD driver binaries or pre-patched driver packages. Users must download the original AMD installer directly from AMD’s official website.

## Long-Term Direction

The current verified release targets only the Radeon Pro 5500M configuration listed above.

In the future, this project may add support for additional Intel Mac AMD GPUs or additional AMD driver versions, but only through separate hardware-specific and driver-specific profiles.

Radeon Pro 5300M support is planned, but it will only be marked as supported after real hardware testing and profile validation are completed.

Additional support must not be assumed. A new profile should only be marked as supported when it has been tested on the exact target Mac model, GPU, hardware ID, Windows version, and AMD driver package.

Planned or experimental areas may include:

* Additional verified driver profiles
* Additional Intel Mac AMD GPU profiles
* Radeon Pro 5300M compatibility work
* Improved non-binary-patched installation workflow
* Read-only GPU/CPU telemetry
* Safer thermal or VRM-stress reduction presets
* Windows power profile helpers
* UI and installation-flow improvements

Low-level hardware tuning, kernel-level CPU controls, undervolting, or ThrottleStop-like features are not part of the current release. If these features are ever explored, they should be separated from the driver installation flow and treated as experimental hardware-control modules.

## Support Status Definitions

| Status | Meaning |
|---|---|
| `Verified` | Tested on the exact target hardware and driver package with successful installation, reboot, and basic functionality checks. |
| `Community Verified` | Confirmed by trusted community testers on the exact target hardware. |
| `Experimental` | Initial testing has been reported or a test profile exists, but stability and recovery behavior are not fully confirmed. |
| `Profile-only` | A profile exists, but it has not been tested on real hardware. |
| `Unsupported` | No valid profile exists, or the hardware/package is known not to work. |

Only `Verified` or clearly documented `Community Verified` profiles should be treated as supported.

## Features

* Downloads the installer from AMD’s official domain
* Verifies installer size and SHA-256
* Automatically detects extracted `Display` and `Display2` packages
* Applies Radeon Pro 5500M compatibility patches
* Uses a profile-based structure for future Radeon Pro 5300M compatibility work
* Creates a local code-signing certificate
* Signs the modified kernel driver and catalog locally
* Backs up and restores existing OEM drivers
* Blocks automatic driver replacement through Windows Update
* Disables Adrenalin update checks and notifications
* Includes Korean and English interfaces
* Displays download percentage, speed, and remaining time

## Why Are Binary Files Modified?

The INF modification alone was not enough for this specific Radeon Pro 5500M Boot Camp setup in testing.

The 2019 MacBook Pro Radeon Pro 5500M uses an Apple-specific hardware ID, and the standard AMD package is not intended to support that exact Boot Camp device as-is.

The current profile applies compatibility changes to:

1. The INF file, to add the exact Radeon Pro 5500M hardware ID and remove the package-level exclusion for that device.
2. `amdgcf.dat`, because the AMD package appears to use internal GPU configuration data in addition to the INF file.
3. `amdkmdag.sys`, because even after the INF change, there appears to be driver-side behavior that prevents this specific package from working correctly on this Boot Camp hardware.

Modifying `amdkmdag.sys` is the most sensitive part of the project because it is a kernel-mode driver. This is why the tool does not redistribute AMD binaries or pre-patched driver packages. It only patches files locally from the official AMD installer downloaded by the user.

The tool checks the original SHA-256 hashes before patching and checks the expected patched hashes afterward. If the files do not exactly match the known AMD 26.6.1 profile used by this tool, the process stops.

If a cleaner method is found that avoids modifying the kernel driver binary, that approach is preferred.

### About the Non-Binary-Patched Test Option

A non-binary-patched 26.6.1 path is being investigated because it would be cleaner and safer than modifying kernel driver binaries.

However, the current AMD Adrenalin 26.6.1 Radeon Pro 5500M workflow still requires binary patching to work correctly in testing.

The non-binary-patched option, if present, should be considered experimental and is currently not expected to work properly.

This option is included only to test whether a cleaner WHQL-friendly or certificate-based workflow can be made reliable in the future.

## Security, Licensing, and Review Status

This project is unofficial and is not affiliated with, endorsed by, sponsored by, or supported by Apple, AMD, or Microsoft.

The author is currently reviewing whether any part of the current approach could raise legal, licensing, security, or distribution concerns.

This project was made public partly to receive feedback from people with experience in driver packaging, Windows security, AMD drivers, and Boot Camp. Feedback, corrections, and technical concerns are welcome.

If it becomes clear that any part of the project is problematic, the repository may be made unavailable or private until the relevant parts are corrected.

## Installation

The application is designed to work best from a clean Windows installation where no AMD graphics driver has been installed.

Mac Secure Boot blocks test-signed drivers, so it must be disabled.

This patch effectively only works while Windows Test Mode is enabled. If you update the AMD driver or turn off Test Mode, the patch may no longer remain applied.

Test-signing mode and disabled Secure Boot reduce the default security protections provided by Windows and Mac firmware. This is a security trade-off.

Avoid using this setup on systems that handle sensitive work, corporate data, financial information, or environments that require strict driver integrity enforcement.

Only use this tool if you understand the implications of test-signed kernel drivers and are comfortable restoring your system if something goes wrong.

### Disable Secure Boot on Intel Mac

* Reboot your Mac while holding Command + R.
* In macOS Recovery, go to Utilities → Startup Security Utility.
* Change Secure Boot to No Security.
* Reboot while holding Option, then select Windows.

### Driver Preparation Flow

1. Run `AMD-BootCamp-Driver-Studio.exe` as administrator.
2. Download the verified AMD installer from the Downloads page.
3. Run the AMD extractor and extract the package to `C:\AMD`.
4. Select **Detect extracted package**.
5. Verify the detected package.
6. Prepare and locally sign the patched package.
7. Enable Windows test-signing mode.
8. Restart Windows.
9. Install the prepared driver.
10. Restart Windows again and confirm that Device Manager reports no error code.

### Installation Guide Status

The current installation flow may not clearly explain every step inside the application.

A dedicated installation guide is planned for a future update so users can better understand what each stage does and when a restart is required.

Future versions are also planned to show clearer success/failure dialogs after installation.

## Important Warning

The prepared package contains a modified kernel-mode driver. Secure Boot must be disabled, and Windows test-signing mode must be enabled.

Test-signing mode may conflict with anti-cheat systems, DRM software, corporate or school security policies, endpoint protection products, and Windows driver integrity checks.

Use this software at your own risk. Back up important data before modifying graphics drivers, boot settings, or security settings.

## AMD Driver Download

AMD driver files are not included in this repository or its releases.

Download the installer directly from the [official AMD 26.6.1 release page](https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-26-6-1.html#Downloads).

## Distribution

The application uses unpackaged WinUI 3 and requires native Windows App SDK files and resources.

Do not distribute or run the EXE by itself. Download the complete ZIP archive from the Releases page and extract all files before running the application.

AMD driver binaries must not be redistributed with this project.

## Adding Driver Profiles

Support for additional verified driver versions or hardware configurations can be added through JSON profiles without rebuilding the application.

Each profile defines:

* Supported hardware IDs
* Official installer URL, size, and SHA-256
* Package root candidates
* Required source-file hashes
* Patch operations and preconditions
* Expected patched hashes
* Driver and catalog paths
* Registry settings
* Support status and testing notes

Only publish profiles verified against the exact official AMD package and exact target hardware.

Do not mark a profile as `Verified` unless it has been tested on real hardware.

## Recovery

When an existing OEM display driver is present, the application exports it before replacement.

Use the **Backups** page to:

* Refresh available backups
* Open the selected backup folder
* Restore a previously exported driver

On a clean Windows installation using the Microsoft Basic Display Adapter, no OEM driver is deleted or backed up.

If a prepared driver causes a black screen, boot failure, Device Manager error, or other serious issue, boot into Windows recovery or Safe Mode and remove or roll back the display driver.

### Known Backup Issue

In the current build, the app may become unresponsive during the backup process after the screen flickers.

This issue is planned to be fixed in a future update.

If the application becomes unresponsive during backup, do not repeatedly start the process again without checking whether a backup folder was partially created.

## Known Risks

This project may cause or contribute to:

* Driver installation failure
* Device Manager error codes such as Code 43 or Code 31
* Black screen or display output issues
* Blue screen or system instability
* Sleep/wake problems
* Game, DRM, or anti-cheat incompatibility
* Conflicts with endpoint protection software
* Loss of Secure Boot and default driver-integrity protections

## What This Tool Does Not Do

This tool does not:

* Include AMD driver binaries
* Distribute modified AMD driver packages
* Bypass AMD, Apple, or Microsoft licensing terms
* Provide official Boot Camp support
* Guarantee stability, performance improvements, or game compatibility
* Support other Mac models or GPUs unless a verified profile is explicitly added
* Mark Radeon Pro 5300M as verified before real hardware testing is completed
* Modify firmware or VBIOS
* Provide current ThrottleStop-like CPU control features

The tool is only a helper application for preparing a compatible driver package locally from an official AMD installer downloaded by the user.

## Creator

Development notes and additional information:

[likeitit.tistory.com/210](https://likeitit.tistory.com/210)

## Legal Notice

This project does not distribute AMD, Apple, or Microsoft proprietary driver binaries.

Users must download the original AMD Software installer directly from AMD’s official website and agree to AMD’s own license terms before using it.

This tool only operates on files already downloaded by the user on their own machine.

This project is not affiliated with, endorsed by, sponsored by, or supported by Apple, AMD, or Microsoft.

All trademarks, product names, driver names, and company names are the property of their respective owners.

## Disclaimer

All product names and trademarks belong to their respective owners.

This repository contains only the helper application and compatibility profiles. It does not contain AMD, Apple, or Microsoft proprietary driver binaries.

---
