# Microsoft Hardware Dev Center attestation workflow

Date: 2026-07-10  
Target: 26.6.4 UMD + 25.2.1 WHQL kernel hybrid for Radeon Pro 5500M Boot Camp

## Why attestation is required

| Constraint | Implication |
|---|---|
| INF modified for Boot Camp `020F106B` | AMD original `u0202073.cat` no longer valid |
| TESTSIGNING OFF mandatory | Local `amdgpu.cat` rejected (`0xC0000428`, confirmed 2026-07-10) |
| No binary patch | Kernel must be original 25.2.1 WHQL bytes, not patched 26.6.x kernel |
| 26.6.4 INF-only impossible | Same AMDGCF gate as 26.6.1 — see `docs/26.6.4-vs-26.6.1-AMDGCF-DIFF.md` |

Attestation provides a Microsoft-trusted replacement catalog without modifying driver binaries.

## Prerequisites

1. [Microsoft Hardware Dev Center](https://partner.microsoft.com/dashboard/hardware) partner account
2. Attestation signing entitlement for the submission
3. Verified source packages on the build machine:
   - 26.6.4 WHQL extract: `C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF`
   - 25.2.1 WHQL anchor: `C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF`
4. `Tools/Verify-OfficialPackages.ps1` PASS

## Step 1 — Export submission package

```powershell
.\Tools\Export-AttestationPackage.ps1 `
  -SoftwareSourceRoot "C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF" `
  -KernelSourceRoot "C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF"
```

Outputs:

| Artifact | Purpose |
|---|---|
| `attestation-hybrid-2664-<stamp>.zip` | Upload bundle |
| `file-hash-manifest.json` | Per-file SHA-256 of prepared package (unsigned catalog) |
| `source-package-evidence.txt` | Original 26.6.4 + 25.2.1 package hashes |
| `SUBMISSION-CHECKLIST.md` | In-zip checklist |

The zip contains the hybrid folder with **no local catalog signature**. Microsoft signs `amdgpu.cat`.

## Step 2 — Hardware Dev Center submission

Submit as a driver package update with attestation signing. Include in the submission notes:

- Hardware ID: `PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`
- INF-only 26.6.4 WHQL fails Boot Camp AMDGCF gate (static analysis attached)
- Hybrid substitutes **only** `amdkmdag.sys` with 25.2.1 WHQL original (`E04E8054…`)
- All other files are unmodified 26.6.4 WHQL bytes
- Local self-signed catalog E2E failed with `0xC0000428` under TESTSIGNING OFF

Attach from the export zip:

- `26.6.4-vs-26.6.1-AMDGCF-DIFF.md`
- `HYBRID-E2E-VALIDATION.md`
- `file-hash-manifest.json`
- `source-package-evidence.txt`

## Step 3 — Receive Microsoft-signed catalog

Save the returned attestation-signed `amdgpu.cat` to a known path, for example:

`C:\AMD\attestation\amdgpu.cat`

Verify before install:

```powershell
$sig = Get-AuthenticodeSignature 'C:\AMD\attestation\amdgpu.cat'
$sig.Status
$sig.SignerCertificate.Subject  # expect CN=Microsoft Windows Hardware Compatibility Publisher
```

## Step 4 — MS-signed hybrid E2E

Requires 25.2.1 anchor baseline (CODE=0, `32.0.12033.5029`, TESTSIGNING OFF).

```powershell
.\Tools\Test-Whql-Hybrid-MsSigned.ps1 `
  -MsSignedCatalogPath "C:\AMD\attestation\amdgpu.cat" `
  -SoftwareSourceRoot "C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF" `
  -KernelSourceRoot "C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF"

# After reboot if exit 3010:
.\Tools\Test-Whql-Hybrid-MsSigned.ps1 -ResumeAfterReboot
```

Pass criteria: see `docs/HYBRID-E2E-VALIDATION.md` (26.6.4 MS-signed section).

Optional clean-install drill: `Tools/Test-Hybrid-Clean-Install.ps1`

## Rejection handling

| Outcome | Next step |
|---|---|
| Microsoft rejects cross-package kernel mix | Escalate AMD official Boot Camp support (`docs/OFFICIAL-CHANNEL-BACKLOG.md`) |
| MS-signed install succeeds, CODE≠0 | Review AMDGCF/runtime compatibility between 25.2.1 kernel and 26.6.4 GCF |
| MS-signed install succeeds, CODE=0, features broken | Document incompatibility; anchor 25.2.1 remains recommended |
| Still `0xC0000428` with MS catalog | Re-check catalog file list matches prepared INF/binary set |

## Status

| Item | State |
|---|---|
| Export tooling | Ready — `Tools/Export-AttestationPackage.ps1` |
| Local signing E2E | **Failed** — documented |
| HDC submission | **Pending** — requires partner account and manual upload |
| MS-signed E2E | **Blocked** — waiting for attestation-signed `amdgpu.cat` |
