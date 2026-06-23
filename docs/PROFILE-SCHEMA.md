# Driver profile schema

프로필은 특정 AMD 패키지와 Boot Camp 하드웨어 조합을 명시적으로 허용하는 JSON 문서입니다. 앱에 내장된 `Profiles` 폴더 또는 아래 시스템 폴더에 추가할 수 있습니다.

```text
%ProgramData%\AMD BootCamp Driver Studio\Profiles
```

동일한 `id`가 있으면 ProgramData 쪽 프로필이 내장 프로필을 덮어씁니다.

## 설계 원칙

- `supportedHardwareIds`는 검증한 전체 하드웨어 ID만 사용합니다.
- 모든 수정 대상 파일은 원본 `sha256`을 가져야 합니다.
- 가능한 경우 `patchedSha256`도 기록합니다.
- 텍스트 치환은 예상 출현 횟수가 정확히 일치해야 합니다.
- 바이너리 수정은 오프셋의 기존 바이트 또는 정수값을 먼저 검사합니다.
- 한 조건이라도 다르면 앱은 수정·서명·설치를 중단합니다.
- 새 릴리스에서 기존 오프셋을 재사용한다고 가정하지 않습니다.

## 최상위 필드

| 필드 | 의미 |
|---|---|
| `schemaVersion` | 현재 `1` |
| `id` | 영구 고유 프로필 ID |
| `displayName` | UI 표시 이름 |
| `marketingVersion` | AMD 공개 릴리스 버전 |
| `packageVersion` | 내부 패키지 버전 |
| `driverVersion` | 설치 후 기대 드라이버 버전 |
| `infName` | 패키지 루트 기준 INF 이름 |
| `kernelDriverPath` | 패키지 루트 기준 커널 SYS 경로 |
| `kernelDriverModified` | 커널 SYS 파일을 패치하는지 여부. 기본값 `true`. `false`이면 커널에 로컬 서명을 적용하지 않고 원본 AMD WHQL 서명을 그대로 유지하며 카탈로그만 로컬 서명함 |
| `catalogFile` | INF가 참조하는 카탈로그 경로 |
| `officialPageUrl` | AMD 공식 릴리스 노트/다운로드 페이지 |
| `installerUrl` | `drivers.amd.com`의 HTTPS 직접 다운로드 URL |
| `installerUrls` | `windows10`, `windows11`별 직접 다운로드 URL. 없으면 `installerUrl`로 대체 |
| `installerFileName` | 저장할 공식 설치 파일명 |
| `installerSha256` | 다운로드 완료 후 반드시 일치해야 하는 SHA-256 |
| `installerSize` | AMD 설치 파일의 예상 바이트 수. 오류 HTML과 불완전 다운로드 차단에 사용 |
| `packageRootCandidates` | 사용자가 상위 폴더나 INF 폴더를 고를 때 탐색할 상대 경로 |
| `supportedHardwareIds` | 허용할 정확한 PnP 하드웨어 ID 목록 |
| `files` | 원본/패치 후 해시 규칙. `patches`가 없는 text-only 프로필에서는 원본 `sha256`만 기록하고 `patchedSha256`은 생략 |
| `patches` | 순서대로 적용할 수정 작업. 텍스트 수정만 필요한 프로필에서는 생략 가능 |
| `registrySettings` | 설치 후 디스플레이 클래스 인스턴스에 적용할 값 |

## 패치 작업

### TextReplace

```json
{
  "type": "TextReplace",
  "file": "driver.inf",
  "search": "exact original text",
  "replacement": "exact replacement text",
  "expectedOccurrences": 1
}
```

### BinaryReplace

```json
{
  "type": "BinaryReplace",
  "file": "bin/driver.sys",
  "offset": 123456,
  "expectedHex": "79",
  "replacementHex": "EB"
}
```

`expectedHex`와 `replacementHex`의 길이는 같아야 합니다.

### BinaryInsert

```json
{
  "type": "BinaryInsert",
  "file": "bin/config.dat",
  "offset": 342,
  "dataHex": "407340",
  "int32Updates": [
    { "offset": 0, "expectedValue": 170, "value": 171 }
  ]
}
```

삽입 후 길이 필드처럼 함께 바뀌어야 하는 32비트 little-endian 정수를 `int32Updates`로 검증·수정합니다.

## 새 버전 추가 체크리스트

1. AMD 공식 패키지를 새 폴더에 압축 해제합니다.
2. 대상 INF 섹션, 하드웨어 제외 규칙, GCF 구조와 커널 검사 분기를 새로 분석합니다.
3. 원본 파일 SHA-256과 모든 패치 전제조건을 기록합니다.
4. 별도 복사본에 패치를 적용하고 패치 후 SHA-256을 계산합니다.
5. 새 JSON을 만들고 `ProfileSelfTest`가 `SELF_TEST=PASS`인지 확인합니다.
6. 테스트 장비에서 백업·설치·재부팅 후 장치 문제 코드 0, 해상도, 절전 복귀, 외부 디스플레이와 Adrenalin을 확인합니다.
7. 검증 완료 전에는 프로필을 다른 사용자에게 배포하지 않습니다.

## kernelDriverModified: false 프로필 작성 지침

커널 SYS 파일을 수정하지 않는 프로필은 `"kernelDriverModified": false`를 선언합니다.

이 경우:
- `files` 배열에서 커널 SYS 항목은 `patchedSha256`을 생략합니다.
- `patches` 배열에서 커널 SYS에 대한 BinaryReplace/BinaryInsert를 사용하지 않습니다.
- `patches` 전체가 TextReplace만으로 구성되거나 비어 있을 수 있습니다.
- 서명 단계에서 카탈로그만 로컬 서명하고 SYS는 원본 AMD WHQL 서명을 유지합니다.

### INF AddReg를 이용한 레지스트리 선주입 패치 예시

`pnputil /add-driver`는 장치 초기화 이전에 INF의 `AddReg` 지시자를 처리합니다.
드라이버 초기화 전에 `KMD_BootCampPlatform` 등의 값이 필요한 경우,
INF의 DDInstall 섹션에 AddReg를 추가하는 TextReplace 패치로 해결할 수 있습니다.

```json
{
  "type": "TextReplace",
  "file": "u0201163.inf",
  "search": "[ati2mtag_Navi14.HW]\r\nHKR,,PageProtectEnable,,0",
  "replacement": "[ati2mtag_Navi14.HW]\r\nHKR,,PageProtectEnable,,0\r\n\r\n[AMD7340.46.HW]\r\nAddReg = AMD7340.46.BootCamp.AddReg\r\n\r\n[AMD7340.46.BootCamp.AddReg]\r\nHKR,,KMD_BootCampPlatform,0x00010001,1\r\nHKR,,PP_Apple_Bootcamp_Enable,0x00010001,1\r\nHKR,,KMD_EnableDisplayableSupport,0x00010001,0\r\nHKR,,EnableUlps,0x00010001,0\r\nHKR,,PP_GfxOffControl,0x00010001,0",
  "expectedOccurrences": 1
}
```

> **주의**: 실제 INF 파일에서 `[ati2mtag_Navi14.HW]` 이하의 정확한 텍스트를 확인한 뒤
> `search` 값을 지정해야 합니다. 위 예시는 구조 설명용이며 실기 검증 전에는 사용하지 않습니다.
