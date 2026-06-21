
# Mac-AMD-GPU-BootCamp-Driver-Studio

<img width="1441" height="1076" alt="Image" src="https://github.com/user-attachments/assets/f9c72b55-dbc0-409e-b8f5-3d442fb734c0" />
<img width="1438" height="933" alt="Image" src="https://github.com/user-attachments/assets/c1804f1c-bc52-4c29-91b5-4613b1f5aabd" />
<img width="1602" height="686" alt="Image" src="https://github.com/user-attachments/assets/423029b9-5e2b-42fa-a1cf-1fe5b6afde38" />

AMD Boot Camp Driver Studio is an unofficial utility that prepares, patches, locally signs, installs, and restores newer AMD Radeon RX 5500M-family drivers for the Radeon Pro 5500M found in the 2019 16-inch MacBook Pro.

## Supported Environment

* MacBook Pro 16-inch, 2019
* AMD Radeon Pro 5500M
* Hardware ID: `PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`
* Windows 10/11 64-bit
* AMD Software: Adrenalin Edition 26.6.1

Other GPUs and driver packages are not supported. The tool stops before making changes unless the hardware ID and required SHA-256 hashes match the selected profile.

## Features

* Downloads the installer from AMD’s official domain
* Verifies installer size and SHA-256
* Automatically detects extracted `Display` and `Display2` packages
* Applies Radeon Pro 5500M compatibility patches
* Creates a local code-signing certificate
* Signs the modified kernel driver and catalog
* Backs up and restores existing OEM drivers
* Blocks automatic driver replacement through Windows Update
* Disables Adrenalin update checks and notifications
* Includes Korean and English interfaces
* Displays download percentage, speed, and remaining time

## Installation

The application is designed to work from a clean Windows installation where no AMD graphics driver has been installed.

Mac Secure Boot blocks test-signed drivers, so it needs to be disabled.

Also, this patch effectively only works while Windows Test Mode is enabled. If you update the AMD driver or turn off Test Mode, the patch will no longer remain applied.

This is not a major issue in normal use, but after applying the patch, I would recommend avoiding suspicious cracked or pirated software. As long as you do that, there should not be any serious security concerns.

Test-signing mode and disabled Secure Boot reduce the default security protections provided by Windows and Mac firmware.

For normal personal use, this may be acceptable to some users, but it is still a security trade-off. Avoid using this setup on systems that handle sensitive work, corporate data, financial information, or environments that require strict driver integrity enforcement.

Only use this tool if you understand the implications of test-signed kernel drivers and are comfortable restoring your system if something goes wrong.

* Reboot your Mac while holding Command + R.
* In macOS Recovery, go to Utilities → Startup Security Utility.
* Change Secure Boot to No Security.
* Reboot while holding Option, then select Windows.

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

This project is not affiliated with or endorsed by Apple, AMD, or Microsoft.

The prepared package contains a modified kernel-mode driver. Secure Boot must be disabled, and Windows test-signing mode must be enabled.

Test-signing mode may conflict with anti-cheat systems, DRM software, corporate security policies, and some endpoint protection products.

Use this software at your own risk. Back up important data before modifying graphics drivers.

## AMD Driver Download

AMD driver files are not included in this repository or its releases.

Download the installer directly from the [official AMD 26.6.1 release page](https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-26-6-1.html#Downloads).

## Distribution

The application uses unpackaged WinUI 3 and requires native Windows App SDK files and resources.

Do not distribute or run the EXE by itself. Download the complete ZIP archive from the Releases page and extract all files before running the application.

AMD driver binaries must not be redistributed with this project.

## Adding Driver Profiles

Support for additional verified driver versions can be added through JSON profiles without rebuilding the application.

Each profile defines:

* Supported hardware IDs
* Official installer URL, size, and SHA-256
* Package root candidates
* Required source-file hashes
* Patch operations and preconditions
* Expected patched hashes
* Driver and catalog paths
* Registry settings

Only publish profiles verified against the exact official AMD package.

## Recovery

When an existing OEM display driver is present, the application exports it before replacement.

Use the **Backups** page to:

* Refresh available backups
* Open the selected backup folder
* Restore a previously exported driver

On a clean Windows installation using the Microsoft Basic Display Adapter, no OEM driver is deleted or backed up.

## Creator

Development notes and additional information:

[likeitit.tistory.com/209](https://likeitit.tistory.com/210)

## Legal Notice

This project does not distribute AMD, Apple, or Microsoft proprietary driver binaries.

Users must download the original AMD Software installer directly from AMD’s official website and agree to AMD’s own license terms before using it.

This tool only operates on files already downloaded by the user on their own machine.

This project is not affiliated with, endorsed by, sponsored by, or supported by Apple, AMD, or Microsoft.

All trademarks, product names, driver names, and company names are the property of their respective owners.

## Security Notice

This utility modifies and locally signs driver files on the user’s own machine. Because the prepared package uses a modified kernel-mode driver, Secure Boot must be disabled and Windows test-signing mode must be enabled.

Disabling Secure Boot and enabling test-signing mode can reduce the security protections normally provided by the operating system and firmware.

This may also cause issues with:

* Anti-cheat systems
* DRM-protected applications
* Corporate or school security policies
* Endpoint protection software
* Windows driver integrity checks

This tool is intended for advanced users who understand these trade-offs and are able to recover their system if a graphics driver installation fails.

Use this software at your own risk. Back up important data before making changes to graphics drivers or boot/security settings.

## What This Tool Does Not Do

This tool does not:

* Include AMD driver binaries
* Distribute modified AMD driver packages
* Bypass AMD, Apple, or Microsoft licensing terms
* Provide official Boot Camp support
* Guarantee stability, performance improvements, or game compatibility
* Support other Mac models or GPUs unless a verified profile is explicitly added

The tool is only a helper application for preparing a compatible driver package locally from an official AMD installer downloaded by the user.

## Disclaimer

All product names and trademarks belong to their respective owners.

This repository contains only the helper application and compatibility profiles. It does not contain AMD, Apple, or Microsoft proprietary driver binaries.

---

# Korean

AMD Boot Camp Driver Studio는 2019 MacBook Pro의 Radeon Pro 5500M에서 최신 AMD Radeon RX 5500M 계열 드라이버를 사용할 수 있도록 패키지 검증, 호환성 패치, 로컬 서명 및 설치를 지원하는 비공식 도구입니다.

## 지원 환경

* MacBook Pro 16-inch, 2019
* AMD Radeon Pro 5500M
* Hardware ID: `PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`
* Windows 10/11 64-bit
* AMD Software: Adrenalin Edition 26.6.1

다른 GPU나 패키지에는 적용되지 않습니다. 모든 하드웨어 ID와 SHA-256이 일치해야 작업이 진행됩니다.

## 주요 기능

* AMD 공식 설치 파일 다운로드 및 SHA-256 검증
* `Display2`를 포함한 압축 해제 패키지 자동 감지
* Radeon Pro 5500M 호환성 패치
* 로컬 코드서명 인증서 생성
* 수정된 드라이버 및 카탈로그 서명
* 기존 OEM 드라이버 백업 및 복원
* Windows Update 드라이버 차단
* Adrenalin 업데이트 알림 억제
* 한국어 및 영어 인터페이스

## 사용 순서

주의점(윈도우에서 Secure Boot끄는 것과 같긴 한데...)
Mac의 Secure Boot가 테스트 서명을 차단하므로 해제 해야합니다.

**또한 윈도우 테스트 모드에서만 사실상 작동하므로, amd 드라이버 업데이트 적용 및 테스트 모드를 끌시에 해당 패치는 모두 적용이 풀리게 됩니다.**
-> 사실 크게 문제는 없습니다만, 패치이후 사용하다가 이상한 복돌 프로그램만 안까시면 보안에는 문제 없으실겁니다.

테스트 서명 모드와 Secure Boot 비활성화는 Windows와 Mac 펌웨어가 기본적으로 제공하는 보안 보호 수준을 낮춥니다.

일반적인 개인 사용 환경에서는 감수 가능한 수준이라고 판단할 수도 있지만, 이는 분명한 보안상 타협입니다. 민감한 업무 자료, 회사 데이터, 금융 정보, 엄격한 드라이버 무결성 검사가 필요한 환경에서는 사용을 권장하지 않습니다.

테스트 서명된 커널 드라이버의 의미를 이해하고, 문제가 발생했을 때 직접 복구할 수 있는 경우에만 사용하는 것을 권장합니다.

* 재부팅하며 Command + R 유지
* macOS 복구 → 유틸리티 → 시동 보안 유틸리티
* Secure Boot를 보안 없음(No Security)으로 변경
* 재부팅하며 Option → Windows 선택

1. AMD 공식 드라이버를 다운로드합니다.
2. AMD 압축 해제기를 실행해 `C:\AMD`에 압축을 풉니다.
3. 압축 해제된 패키지를 감지하고 검증합니다.
4. 패치 및 서명된 설치 패키지를 준비합니다.
5. 테스트 서명 모드를 활성화하고 Windows를 재부팅합니다.
6. 드라이버를 설치한 뒤 다시 재부팅합니다.

## 중요 경고

이 도구는 Microsoft 또는 AMD의 공식 제품이 아닙니다.

수정된 커널 드라이버를 사용하므로 Secure Boot를 끄고 Windows 테스트 서명 모드를 활성화해야 합니다. 일부 안티치트, DRM 및 보안 프로그램과 충돌할 수 있습니다.

사용에 따른 시스템 불안정, 데이터 손실 또는 하드웨어 문제의 책임은 사용자에게 있습니다. 중요한 자료를 먼저 백업하세요.

## AMD 드라이버

AMD 드라이버는 이 저장소에 포함하지 않습니다. 사용자가 [AMD 공식 26.6.1 페이지](https://www.amd.com/ko/resources/support-articles/release-notes/RN-RAD-WIN-26-6-1.html#Downloads)에서 직접 다운로드합니다.

## 배포

WinUI 3 네이티브 파일이 필요하므로 EXE만 따로 복사하면 실행되지 않습니다. Releases에 등록된 ZIP 전체를 압축 해제해 사용하세요.

## 복구

기존 OEM 디스플레이 드라이버가 있는 경우, 이 도구는 교체 전에 해당 드라이버를 내보내 백업합니다.

Backups 페이지에서 다음 작업을 할 수 있습니다.

* 사용 가능한 백업 새로고침
* 선택한 백업 폴더 열기
* 이전에 내보낸 드라이버 복원

깨끗한 Windows 설치 상태에서 Microsoft Basic Display Adapter만 사용 중인 경우에는 삭제되거나 백업되는 OEM 드라이버가 없습니다.

## 제작자

[제작 과정 및 설명](https://likeitit.tistory.com/210)

## 법적 고지

이 프로젝트는 AMD, Apple, Microsoft의 독점 드라이버 바이너리를 배포하지 않습니다.

사용자는 AMD 공식 웹사이트에서 원본 AMD Software 설치 파일을 직접 다운로드해야 하며, AMD의 라이선스 약관에 동의한 뒤 사용해야 합니다.

이 도구는 사용자가 본인의 컴퓨터에 직접 다운로드한 파일을 로컬 환경에서 처리하는 보조 도구입니다.

이 프로젝트는 Apple, AMD, Microsoft와 관련이 없으며, 해당 회사들의 공식 지원, 보증, 후원 또는 승인을 받은 프로젝트가 아닙니다.

모든 상표, 제품명, 드라이버명, 회사명은 각 소유자의 자산입니다.

## 보안 관련 안내

이 유틸리티는 사용자의 컴퓨터에서 드라이버 파일을 수정하고 로컬 서명을 적용합니다. 준비된 패키지는 수정된 커널 모드 드라이버를 사용하므로, Mac의 Secure Boot를 비활성화하고 Windows 테스트 서명 모드를 활성화해야 합니다.

Secure Boot를 끄고 테스트 서명 모드를 사용하는 것은 운영체제와 펌웨어가 기본적으로 제공하는 보안 보호 수준을 낮출 수 있습니다.

또한 다음과 같은 프로그램 또는 환경과 충돌할 수 있습니다.

* 안티치트 시스템
* DRM이 적용된 프로그램
* 회사 또는 학교의 보안 정책
* 엔드포인트 보안 프로그램
* Windows 드라이버 무결성 검사

이 도구는 이러한 위험을 이해하고, 그래픽 드라이버 설치 실패 시 직접 복구할 수 있는 사용자를 대상으로 합니다.

사용에 따른 모든 책임은 사용자 본인에게 있습니다. 그래픽 드라이버나 부팅/보안 설정을 변경하기 전 중요한 데이터는 반드시 백업하는 것을 권장합니다.

## 이 도구가 하지 않는 것

이 도구는 다음을 제공하지 않습니다.

* AMD 드라이버 바이너리 포함
* 수정된 AMD 드라이버 패키지 배포
* AMD, Apple, Microsoft의 라이선스 우회
* 공식 Boot Camp 지원
* 안정성, 성능 향상, 게임 호환성 보장
* 검증된 프로필이 없는 다른 Mac 모델 또는 GPU 지원

이 도구는 사용자가 AMD 공식 설치 파일을 직접 다운로드한 뒤, 해당 파일을 로컬 환경에서 호환 패키지로 준비하는 것을 돕는 보조 유틸리티입니다.
