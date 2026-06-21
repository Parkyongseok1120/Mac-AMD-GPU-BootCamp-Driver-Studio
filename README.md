# Mac-AMD-GPU-BootCamp-Driver-Studio

AMD Boot Camp Driver Studio is an unofficial utility that prepares, patches, locally signs, installs, and restores newer AMD Radeon RX 5500M-family drivers for the Radeon Pro 5500M found in the 2019 16-inch MacBook Pro.

## Supported Environment

- MacBook Pro 16-inch, 2019
- AMD Radeon Pro 5500M
- Hardware ID: `PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`
- Windows 10/11 64-bit
- AMD Software: Adrenalin Edition 26.6.1

Other GPUs and driver packages are not supported. The tool stops before making changes unless the hardware ID and required SHA-256 hashes match the selected profile.

## Features

- Downloads the installer from AMD’s official domain
- Verifies installer size and SHA-256
- Automatically detects extracted `Display` and `Display2` packages
- Applies Radeon Pro 5500M compatibility patches
- Creates a local code-signing certificate
- Signs the modified kernel driver and catalog
- Backs up and restores existing OEM drivers
- Blocks automatic driver replacement through Windows Update
- Disables Adrenalin update checks and notifications
- Includes Korean and English interfaces
- Displays download percentage, speed, and remaining time

## Installation

The application is designed to work from a clean Windows installation where no AMD graphics driver has been installed.

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

- Supported hardware IDs
- Official installer URL, size, and SHA-256
- Package root candidates
- Required source-file hashes
- Patch operations and preconditions
- Expected patched hashes
- Driver and catalog paths
- Registry settings

Only publish profiles verified against the exact official AMD package.

## Recovery

When an existing OEM display driver is present, the application exports it before replacement.

Use the **Backups** page to:

- Refresh available backups
- Open the selected backup folder
- Restore a previously exported driver

On a clean Windows installation using the Microsoft Basic Display Adapter, no OEM driver is deleted or backed up.

## Creator

Development notes and additional information:

[likeitit.tistory.com/209](https://likeitit.tistory.com/209)

## Disclaimer

All product names and trademarks belong to their respective owners.

This repository contains only the helper application and compatibility profiles. It does not contain AMD, Apple, or Microsoft proprietary driver binaries.



---
# Korean

AMD Boot Camp Driver Studio는 2019 MacBook Pro의 Radeon Pro 5500M에서 최신 AMD Radeon RX 5500M 계열 드라이버를 사용할 수 있도록 패키지 검증, 호환성 패치, 로컬 서명 및 설치를 지원하는 비공식 도구입니다.

## 지원 환경

- MacBook Pro 16-inch, 2019
- AMD Radeon Pro 5500M
- Hardware ID: `PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`
- Windows 10/11 64-bit
- AMD Software: Adrenalin Edition 26.6.1

다른 GPU나 패키지에는 적용되지 않습니다. 모든 하드웨어 ID와 SHA-256이 일치해야 작업이 진행됩니다.

## 주요 기능

- AMD 공식 설치 파일 다운로드 및 SHA-256 검증
- `Display2`를 포함한 압축 해제 패키지 자동 감지
- Radeon Pro 5500M 호환성 패치
- 로컬 코드서명 인증서 생성
- 수정된 드라이버 및 카탈로그 서명
- 기존 OEM 드라이버 백업 및 복원
- Windows Update 드라이버 차단
- Adrenalin 업데이트 알림 억제
- 한국어 및 영어 인터페이스

## 사용 순서

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

## 제작자

[제작 과정 및 설명](https://likeitit.tistory.com/209)
