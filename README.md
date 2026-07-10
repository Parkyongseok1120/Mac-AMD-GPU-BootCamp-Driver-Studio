# Mac AMD GPU BootCamp Driver Studio Release 1.1.0

<img width="1741" height="972" alt="스크린샷 2026-06-23 202959" src="https://github.com/user-attachments/assets/879d88b5-d19f-4f8d-a515-ec1a1a76ae43" />

<img width="1717" height="1209" alt="스크린샷 2026-06-23 195454" src="https://github.com/user-attachments/assets/43cbaf70-1ad2-4f93-8e42-82b5a907f307" />

AMD Boot Camp Driver Studio is an unofficial utility that prepares, verifies, locally signs, installs, backs up, and restores a compatible AMD driver package for the Radeon Pro 5500M found in the 2019 16-inch MacBook Pro.

This project is currently limited to a specific Boot Camp setup. It is not a universal AMD Boot Camp driver package.

## Current Supported Environment

* MacBook Pro 16-inch, 2019
* AMD Radeon Pro 5500M
* Hardware ID: `PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`
* Windows 10/11 64-bit through Boot Camp
* **AMD Software: Adrenalin Edition 25.2.1 (Verified WHQL anchor)**

Other GPUs, Mac models, and driver packages are not currently supported unless a matching verified profile is explicitly added.

The tool stops before making changes unless the detected hardware ID, package structure, file size, and required SHA-256 hashes match the selected profile.

## Discontinued paths

**Due to copyright, EULA, and related licensing concerns, distribution of 26.6.x patch workflows has been discontinued.** AMD Adrenalin **26.6.1** and **26.6.4** profiles and experimental recipes have been **removed** from this repository and will not be maintained or released.

Supporting context from prior local validation (not offered as a workaround):

* INF-only 26.6.x failed on target hardware (AMDGCF kernel gate)
* 25.2.1 kernel + 26.6.4 UMD hybrid failed with device configuration error (`0xC0000182`) even after full kernel-data matching
* Binary-patched 26.6.1 required test signing and raised additional redistribution and modification concerns

The **25.2.1 WHQL anchor** is the only supported path in this project. It modifies only the INF and catalog — no driver binaries are patched. Users must obtain the original AMD installer from AMD's official website and comply with AMD's license terms.

> **정책 안내 (한국어)**
>
> 저작권, EULA(최종 사용자 사용권 계약), 드라이버 재배포 및 수정 관련 검토 결과, **26.6.x 패치 배포 및 프로필 유지를 중단**했습니다.
> 이 저장소에서는 AMD Adrenalin 26.6.1 / 26.6.4 호환 레시피를 더 이상 제공·유지하지 않으며, 제거된 26.6.x 패치 프로필의 재배포나 포크 요청에 응하지 않습니다.
> 지원 경로는 **25.2.1 WHQL 앵커**뿐이며, AMD 공식 설치 프로그램을 사용자가 직접 받아 AMD 라이선스 조건을 준수해야 합니다.

## Project Goal

The goal of this project is to make a reproducible local workflow for preparing a compatible AMD driver package on unsupported Boot Camp hardware.

It is intended to avoid repeated manual file editing by making the process explicit, profile-based, hash-checked, locally signed, and recoverable.

The project does not redistribute AMD driver binaries or pre-patched driver packages. Users must download the original AMD installer directly from AMD's official website.

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

* Downloads the installer from AMD's official domain
* Verifies installer size and SHA-256
* Automatically detects extracted `Display` packages
* Applies Radeon Pro 5500M compatibility patches to the INF only
* Creates a local code-signing certificate
* Signs the modified catalog locally
* Backs up and restores existing OEM drivers
* Blocks automatic driver replacement through Windows Update
* Disables Adrenalin update checks and notifications
* Includes Korean and English interfaces
* Displays download percentage, speed, and remaining time

## Security, Licensing, and Review Status

This project is unofficial and is not affiliated with, endorsed by, sponsored by, or supported by Apple, AMD, or Microsoft.

**26.6.x patch distribution is discontinued.** After review of copyright, EULA, and driver redistribution rules, this repository no longer ships or documents 26.6.1 / 26.6.4 compatibility recipes. Do not request, fork, or redistribute removed 26.6.x patch profiles from this project.

The 25.2.1 WHQL anchor profile does **not** require disabling Mac Secure Boot or enabling Windows Test Mode, and does not patch AMD driver binaries.

## Installation

The application is designed to work best from a clean Windows installation where no AMD graphics driver has been installed.

### Driver Preparation Flow

1. Run `AMD-BootCamp-Driver-Studio.exe` as administrator.
2. Download the verified AMD 25.2.1 installer from the Downloads page.
3. Run the AMD extractor and extract the package to `C:\AMD`.
4. Select **Detect extracted package**.
5. Verify the detected package.
6. Prepare the driver package.
7. Install the prepared driver.
8. Restart Windows if required and confirm that Device Manager reports no error code.

## AMD Driver Download

AMD driver files are not included in this repository or its releases.

Download the installer directly from the [official AMD 25.2.1 release page](https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-25-2-1.html#Downloads).

## Distribution

The application uses unpackaged WinUI 3 and requires native Windows App SDK files and resources.

Do not distribute or run the EXE by itself. Download the complete ZIP archive from the Releases page and extract all files before running the application.

AMD driver binaries must not be redistributed with this project.

## Adding Driver Profiles

Support for additional verified driver versions or hardware configurations can be added through JSON profiles without rebuilding the application.

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

## Known Risks

This project may cause or contribute to:

* Driver installation failure
* Device Manager error codes such as Code 43 or Code 31
* Black screen or display output issues
* Blue screen or system instability
* Sleep/wake problems
* Game, DRM, or anti-cheat incompatibility
* Conflicts with endpoint protection software

## What This Tool Does Not Do

This tool does not:

* Include AMD driver binaries
* Distribute modified AMD driver packages
* Bypass AMD, Apple, or Microsoft licensing terms
* Provide official Boot Camp support
* Guarantee stability, performance improvements, or game compatibility
* Support other Mac models or GPUs unless a verified profile is explicitly added
* Modify firmware or VBIOS

The tool is only a helper application for preparing a compatible driver package locally from an official AMD installer downloaded by the user.

## Creator

Development notes and additional information:

[likeitit.tistory.com/210](https://likeitit.tistory.com/210)

## Legal Notice

This project does not distribute AMD, Apple, or Microsoft proprietary driver binaries.

Users must download the original AMD Software installer directly from AMD's official website and agree to AMD's own license terms before using it.

This tool only operates on files already downloaded by the user on their own machine.

This project is not affiliated with, endorsed by, sponsored by, or supported by Apple, AMD, or Microsoft.

All trademarks, product names, driver names, and company names are the property of their respective owners.

## Disclaimer

All product names and trademarks belong to their respective owners.

This repository contains only the helper application and compatibility profiles. It does not contain AMD, Apple, or Microsoft proprietary driver binaries.

---
