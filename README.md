# Mac-AMD-GPU-BootCamp-Driver-Studio

<img width="1441" height="1076" alt="Image" src="https://github.com/user-attachments/assets/f9c72b55-dbc0-409e-b8f5-3d442fb734c0" />
<img width="1438" height="933" alt="Image" src="https://github.com/user-attachments/assets/c1804f1c-bc52-4c29-91b5-4613b1f5aabd" />
<img width="1602" height="686" alt="Image" src="https://github.com/user-attachments/assets/423029b9-5e2b-42fa-a1cf-1fe5b6afde38" />

AMD Boot Camp Driver Studio is an unofficial utility that prepares, verifies, patches, locally signs, installs, backs up, and restores a newer AMD Radeon RX 5500M-family driver package for the Radeon Pro 5500M found in the 2019 16-inch MacBook Pro.

This project is currently limited to one specific Boot Camp setup. It is not a universal AMD Boot Camp driver package.

## Current Supported Environment

* MacBook Pro 16-inch, 2019
* AMD Radeon Pro 5500M
* Hardware ID: `PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`
* Windows 10/11 64-bit through Boot Camp
* AMD Software: Adrenalin Edition 26.6.1

Other GPUs, Mac models, and driver packages are not currently supported. The tool stops before making changes unless the detected hardware ID, package structure, file size, and required SHA-256 hashes match the selected profile.

## Project Goal

The goal of this project is to make a reproducible local workflow for preparing a compatible AMD driver package on unsupported Boot Camp hardware.

It is intended to avoid repeated manual file editing by making the process explicit, profile-based, hash-checked, locally signed, and recoverable.

The project does not redistribute AMD driver binaries or pre-patched driver packages. Users must download the original AMD installer directly from AMD’s official website.

## Long-Term Direction

The current release targets only the Radeon Pro 5500M configuration listed above.

In the future, this project may add support for additional Intel Mac AMD GPUs or additional AMD driver versions, but only through separate hardware-specific and driver-specific profiles.

Additional support must not be assumed. A new profile should only be marked as supported when it has been tested on the exact target Mac model, GPU, hardware ID, Windows version, and AMD driver package.

Planned or experimental areas may include:

* Additional verified driver profiles
* Additional Intel Mac AMD GPU profiles
* Read-only GPU/CPU telemetry
* Safer thermal or VRM-stress reduction presets
* Windows power profile helpers

Low-level hardware tuning, kernel-level CPU controls, undervolting, or ThrottleStop-like features are not part of the current release. If these features are ever explored, they should be separated from the driver installation flow and treated as experimental hardware-control modules.

## Support Status Definitions

| Status | Meaning |
|---|---|
| `Verified` | Tested on the exact target hardware and driver package with successful installation, reboot, and basic functionality checks. |
| `Community Verified` | Confirmed by trusted community testers on the exact target hardware. |
| `Experimental` | Initial testing has been reported, but stability and recovery behavior are not fully confirmed. |
| `Profile-only` | A profile exists, but it has not been tested on real hardware. |
| `Unsupported` | No valid profile exists, or the hardware/package is known not to work. |

Only `Verified` or clearly documented `Community Verified` profiles should be treated as supported.

## Features

* Downloads the installer from AMD’s official domain
* Verifies installer size and SHA-256
* Automatically detects extracted `Display` and `Display2` packages
* Applies Radeon Pro 5500M compatibility patches
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

# Korean

AMD Boot Camp Driver Studio는 2019 MacBook Pro 16인치의 Radeon Pro 5500M에서 최신 AMD Radeon RX 5500M 계열 드라이버 패키지를 사용할 수 있도록 패키지 검증, 호환성 패치, 로컬 서명, 설치, 백업 및 복원을 지원하는 비공식 도구입니다.

이 프로젝트는 현재 특정 Boot Camp 환경 하나를 대상으로 합니다. 범용 AMD Boot Camp 드라이버 패키지가 아닙니다.

## 현재 지원 환경

* MacBook Pro 16-inch, 2019
* AMD Radeon Pro 5500M
* Hardware ID: `PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`
* Windows 10/11 64-bit through Boot Camp
* AMD Software: Adrenalin Edition 26.6.1

다른 GPU, Mac 모델, 드라이버 패키지는 현재 지원하지 않습니다. 감지된 하드웨어 ID, 패키지 구조, 파일 크기, SHA-256 해시가 선택된 프로필과 일치하지 않으면 작업은 진행되지 않습니다.

## 프로젝트 목적

이 프로젝트의 목적은 지원이 중단되거나 불완전한 Boot Camp 환경에서 사용할 수 있는 AMD 드라이버 패키지를 사용자의 로컬 환경에서 재현 가능하게 준비하는 것입니다.

반복적인 수동 파일 편집을 줄이고, 프로필 기반 검증, 해시 확인, 로컬 서명, 백업 및 복구 절차를 명확하게 만드는 것을 목표로 합니다.

이 프로젝트는 AMD 드라이버 바이너리나 미리 패치된 드라이버 패키지를 재배포하지 않습니다. 사용자는 AMD 공식 웹사이트에서 원본 AMD 설치 파일을 직접 다운로드해야 합니다.

## 장기 방향

현재 릴리스는 위에 명시된 Radeon Pro 5500M 구성만 대상으로 합니다.

향후에는 일부 Intel Mac AMD GPU 또는 추가 AMD 드라이버 버전을 지원할 수 있습니다. 단, 이 경우에도 하드웨어별, 드라이버 버전별로 분리된 검증 프로필을 통해서만 지원할 예정입니다.

추가 지원은 자동으로 보장되지 않습니다. 새로운 프로필은 정확한 대상 Mac 모델, GPU, 하드웨어 ID, Windows 버전, AMD 드라이버 패키지에서 실제 테스트가 완료된 경우에만 지원 대상으로 표시되어야 합니다.

향후 검토 가능한 영역은 다음과 같습니다.

* 추가 검증 드라이버 프로필
* 추가 Intel Mac AMD GPU 프로필
* 읽기 전용 GPU/CPU 텔레메트리
* VRM 부담을 줄이기 위한 안전한 온도/전력 프리셋
* Windows 전원 프로필 보조 기능

저수준 하드웨어 튜닝, 커널 레벨 CPU 제어, 언더볼팅, ThrottleStop과 유사한 기능은 현재 릴리스에 포함되어 있지 않습니다. 만약 이런 기능을 검토하더라도 드라이버 설치 흐름과 분리된 실험적 하드웨어 제어 모듈로 다루는 것이 맞다고 봅니다.

## 지원 상태 정의

| 상태 | 의미 |
|---|---|
| `Verified` | 정확한 대상 하드웨어와 드라이버 패키지에서 설치, 재부팅, 기본 기능 확인까지 테스트된 상태입니다. |
| `Community Verified` | 신뢰 가능한 커뮤니티 테스터가 정확한 대상 하드웨어에서 확인한 상태입니다. |
| `Experimental` | 초기 성공 보고는 있으나 안정성 및 복구 동작이 충분히 확인되지 않은 상태입니다. |
| `Profile-only` | 프로필은 존재하지만 실제 하드웨어에서 테스트되지 않은 상태입니다. |
| `Unsupported` | 유효한 프로필이 없거나, 해당 하드웨어/패키지가 동작하지 않는 것으로 확인된 상태입니다. |

`Verified` 또는 명확히 문서화된 `Community Verified` 프로필만 지원 대상으로 간주해야 합니다.

## 주요 기능

* AMD 공식 도메인에서 설치 파일 다운로드
* 설치 파일 크기 및 SHA-256 검증
* 압축 해제된 `Display` 및 `Display2` 패키지 자동 감지
* Radeon Pro 5500M 호환성 패치
* 로컬 코드서명 인증서 생성
* 수정된 커널 드라이버 및 카탈로그 로컬 서명
* 기존 OEM 드라이버 백업 및 복원
* Windows Update를 통한 자동 드라이버 교체 차단
* Adrenalin 업데이트 확인 및 알림 비활성화
* 한국어 및 영어 인터페이스
* 다운로드 진행률, 속도, 남은 시간 표시

## 왜 바이너리 파일을 수정하나요?

테스트 결과, 이 특정 Radeon Pro 5500M Boot Camp 환경에서는 INF 수정만으로 충분하지 않았습니다.

2019 MacBook Pro의 Radeon Pro 5500M은 Apple 전용 하드웨어 ID를 사용하며, AMD 표준 패키지는 이 Boot Camp 장치를 그대로 지원하도록 만들어진 것이 아닙니다.

현재 프로필은 다음 파일에 호환성 수정을 적용합니다.

1. INF 파일: 정확한 Radeon Pro 5500M 하드웨어 ID를 추가하고, 해당 장치에 대한 패키지 레벨의 제외 설정을 제거합니다.
2. `amdgcf.dat`: AMD 패키지가 INF 파일 외에도 내부 GPU 구성 데이터를 사용하는 것으로 보이기 때문에 수정합니다.
3. `amdkmdag.sys`: INF 변경 이후에도 이 특정 패키지가 해당 Boot Camp 하드웨어에서 정상 동작하지 못하게 하는 드라이버 내부 동작이 있는 것으로 보여 수정합니다.

`amdkmdag.sys`는 커널 모드 드라이버이기 때문에 이 파일을 수정하는 부분이 프로젝트에서 가장 민감한 부분입니다. 그래서 이 도구는 AMD 바이너리나 미리 패치된 드라이버 패키지를 재배포하지 않습니다. 사용자가 AMD 공식 설치 파일을 직접 다운로드한 뒤, 그 파일을 로컬 환경에서만 패치합니다.

또한 패치 전에는 원본 SHA-256 해시를 확인하고, 패치 후에는 예상되는 패치 결과 해시를 다시 확인합니다. 파일이 이 도구에서 사용하는 AMD 26.6.1 프로필과 정확히 일치하지 않으면 작업은 중단됩니다.

커널 드라이버 바이너리를 수정하지 않는 더 깔끔한 방법이 발견된다면, 그 방향을 우선하는 것이 맞다고 봅니다.

## 보안, 라이선스, 검토 상태

이 프로젝트는 비공식 프로젝트이며 Apple, AMD, Microsoft와 관련이 없고, 해당 회사들의 승인, 후원, 보증, 지원을 받은 프로젝트가 아닙니다.

현재 방식 중 일부가 법적, 라이선스, 보안, 배포 측면에서 문제가 될 수 있는지 확인 중입니다.

이 프로젝트를 공개한 이유 중 하나는 드라이버 패키징, Windows 보안, AMD 드라이버, Boot Camp에 경험이 있는 분들의 피드백을 받기 위해서입니다. 피드백, 수정할 점, 기술적인 우려 사항은 환영합니다.

만약 프로젝트의 특정 부분이 문제가 된다는 점이 명확해진다면, 해당 부분을 수정하기 전까지 저장소를 임시로 비공개 처리하거나 접근할 수 없도록 할 수 있습니다.

## 사용 순서

이 애플리케이션은 AMD 그래픽 드라이버가 아직 설치되지 않은 깨끗한 Windows 설치 상태에서 사용하는 것을 권장합니다.

Mac의 Secure Boot는 테스트 서명된 드라이버를 차단하므로 비활성화해야 합니다.

또한 이 패치는 사실상 Windows 테스트 모드가 활성화된 상태에서만 동작합니다. AMD 드라이버를 업데이트하거나 테스트 모드를 끄면 패치가 더 이상 유지되지 않을 수 있습니다.

테스트 서명 모드와 Secure Boot 비활성화는 Windows와 Mac 펌웨어가 기본적으로 제공하는 보안 보호 수준을 낮춥니다. 이는 명확한 보안상 타협입니다.

민감한 업무 자료, 회사 데이터, 금융 정보, 엄격한 드라이버 무결성 검사가 필요한 환경에서는 사용을 권장하지 않습니다.

테스트 서명된 커널 드라이버의 의미를 이해하고, 문제가 발생했을 때 직접 복구할 수 있는 경우에만 사용하는 것을 권장합니다.

### Intel Mac에서 Secure Boot 비활성화

* 재부팅하며 Command + R 유지
* macOS 복구 → 유틸리티 → 시동 보안 유틸리티
* Secure Boot를 보안 없음(No Security)으로 변경
* 재부팅하며 Option → Windows 선택

### 드라이버 준비 흐름

1. `AMD-BootCamp-Driver-Studio.exe`를 관리자 권한으로 실행합니다.
2. Downloads 페이지에서 검증된 AMD 설치 파일을 다운로드합니다.
3. AMD 압축 해제기를 실행해 패키지를 `C:\AMD`에 압축 해제합니다.
4. **Detect extracted package**를 선택합니다.
5. 감지된 패키지를 검증합니다.
6. 패치 및 로컬 서명된 설치 패키지를 준비합니다.
7. Windows 테스트 서명 모드를 활성화합니다.
8. Windows를 재부팅합니다.
9. 준비된 드라이버를 설치합니다.
10. 다시 Windows를 재부팅한 뒤 장치 관리자에서 오류 코드가 없는지 확인합니다.

## 중요 경고

준비된 패키지는 수정된 커널 모드 드라이버를 포함합니다. Secure Boot를 비활성화하고 Windows 테스트 서명 모드를 활성화해야 합니다.

테스트 서명 모드는 안티치트 시스템, DRM 소프트웨어, 회사 또는 학교 보안 정책, 엔드포인트 보안 제품, Windows 드라이버 무결성 검사와 충돌할 수 있습니다.

사용에 따른 모든 책임은 사용자 본인에게 있습니다. 그래픽 드라이버, 부팅 설정, 보안 설정을 변경하기 전 중요한 데이터는 반드시 백업하세요.

## AMD 드라이버 다운로드

AMD 드라이버 파일은 이 저장소나 릴리스에 포함되어 있지 않습니다.

사용자는 [AMD 공식 26.6.1 페이지](https://www.amd.com/ko/resources/support-articles/release-notes/RN-RAD-WIN-26-6-1.html#Downloads)에서 직접 설치 파일을 다운로드해야 합니다.

## 배포

이 애플리케이션은 unpackaged WinUI 3 기반이며 Windows App SDK 네이티브 파일과 리소스가 필요합니다.

EXE만 따로 배포하거나 실행하지 마세요. Releases 페이지의 ZIP 전체를 다운로드하고 모든 파일을 압축 해제한 뒤 실행해야 합니다.

AMD 드라이버 바이너리는 이 프로젝트와 함께 재배포하면 안 됩니다.

## 드라이버 프로필 추가

추가 드라이버 버전 또는 하드웨어 구성 지원은 애플리케이션을 다시 빌드하지 않고 JSON 프로필을 통해 추가할 수 있습니다.

각 프로필은 다음을 정의합니다.

* 지원 하드웨어 ID
* 공식 설치 파일 URL, 크기, SHA-256
* 패키지 루트 후보
* 필요한 원본 파일 해시
* 패치 작업 및 사전 조건
* 예상되는 패치 후 해시
* 드라이버 및 카탈로그 경로
* 레지스트리 설정
* 지원 상태 및 테스트 기록

정확한 AMD 공식 패키지와 정확한 대상 하드웨어에서 검증된 프로필만 공개해야 합니다.

실제 하드웨어에서 테스트되지 않은 프로필은 `Verified`로 표시하면 안 됩니다.

## 복구

기존 OEM 디스플레이 드라이버가 있는 경우, 이 도구는 교체 전에 해당 드라이버를 내보내 백업합니다.

Backups 페이지에서 다음 작업을 할 수 있습니다.

* 사용 가능한 백업 새로고침
* 선택한 백업 폴더 열기
* 이전에 내보낸 드라이버 복원

깨끗한 Windows 설치 상태에서 Microsoft Basic Display Adapter만 사용 중인 경우에는 삭제되거나 백업되는 OEM 드라이버가 없습니다.

준비된 드라이버로 인해 블랙스크린, 부팅 실패, 장치 관리자 오류, 기타 심각한 문제가 발생하면 Windows 복구 환경 또는 안전 모드로 진입해 디스플레이 드라이버를 제거하거나 롤백하세요.

## 알려진 위험

이 프로젝트는 다음 문제를 유발하거나 그 원인이 될 수 있습니다.

* 드라이버 설치 실패
* Code 43 또는 Code 31 같은 장치 관리자 오류
* 블랙스크린 또는 디스플레이 출력 문제
* 블루스크린 또는 시스템 불안정
* 절전/복귀 문제
* 게임, DRM, 안티치트 호환성 문제
* 엔드포인트 보안 소프트웨어와의 충돌
* Secure Boot 및 기본 드라이버 무결성 보호 상실

## 이 도구가 하지 않는 것

이 도구는 다음을 제공하지 않습니다.

* AMD 드라이버 바이너리 포함
* 수정된 AMD 드라이버 패키지 배포
* AMD, Apple, Microsoft의 라이선스 우회
* 공식 Boot Camp 지원
* 안정성, 성능 향상, 게임 호환성 보장
* 검증된 프로필이 없는 다른 Mac 모델 또는 GPU 지원
* 펌웨어 또는 VBIOS 수정
* 현재 ThrottleStop과 유사한 CPU 제어 기능

이 도구는 사용자가 AMD 공식 설치 파일을 직접 다운로드한 뒤, 해당 파일을 로컬 환경에서 호환 패키지로 준비하는 것을 돕는 보조 애플리케이션입니다.

## 제작자

제작 과정 및 추가 설명:

[likeitit.tistory.com/210](https://likeitit.tistory.com/210)

## 법적 고지

이 프로젝트는 AMD, Apple, Microsoft의 독점 드라이버 바이너리를 배포하지 않습니다.

사용자는 AMD 공식 웹사이트에서 원본 AMD Software 설치 파일을 직접 다운로드해야 하며, AMD의 라이선스 약관에 동의한 뒤 사용해야 합니다.

이 도구는 사용자가 본인의 컴퓨터에 직접 다운로드한 파일을 로컬 환경에서 처리하는 보조 도구입니다.

이 프로젝트는 Apple, AMD, Microsoft와 관련이 없으며, 해당 회사들의 공식 지원, 보증, 후원 또는 승인을 받은 프로젝트가 아닙니다.

모든 상표, 제품명, 드라이버명, 회사명은 각 소유자의 자산입니다.

## 면책 조항

모든 제품명과 상표는 각 소유자의 자산입니다.

이 저장소에는 보조 애플리케이션과 호환성 프로필만 포함됩니다. AMD, Apple, Microsoft의 독점 드라이버 바이너리는 포함하지 않습니다.
