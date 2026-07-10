# Hybrid E2E validation log

Date: 2026-07-10  
Target: MacBook Pro 16-inch 2019, Radeon Pro 5500M (`PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`)

## Completed offline checks

| Step | Tool | Result |
|---|---|---|
| Official package SHA verification | `Tools/Verify-OfficialPackages.ps1` | PASS |
| Hybrid package preparation | `Tools/Test-Whql-Hybrid-26.6.1-25.2.1.ps1 -PrepareOnly` | PASS |
| App/profile pipeline | `Tools/ProfileSelfTest/ProfileSelfTest.csproj` | `SELF_TEST=PASS` |
| Runtime assertions | prepared hybrid package | kernel `E04E8054…`, UMD `93927BB0…`, GCF `D1AC965F…` |

Prepared package example:

`C:\AMD\BootCampDriverStudio\Prepared\AMD-26.6.1-with-25.2.1-kernel-20260710-174038`

## Current machine baseline

Captured by `Tools/Test-Anchor-Status.ps1`:

| Check | Value |
|---|---|
| GPU problem code | `0` |
| Driver version | `32.0.21043.12001` |
| Active INF | `oem105.inf` |
| Loaded kernel SHA | `D572AB6F…` (legacy patched, not official 26.6.1 or 25.2.1) |
| TESTSIGNING | **ON** |
| Secure Boot | `False` |
| Anchor-ready baseline | **False** |

## Why full install E2E did not run automatically

The destructive hardware path requires all of the following before install:

1. `TESTSIGNING=OFF` and reboot (`Tools/Disable-TestSigning.ps1`)
2. Active 25.2.1 WHQL anchor: problem code `0`, version `32.0.12033.5029`
3. Admin PowerShell ready for `-ResumeAfterReboot`

The current machine is running a legacy patched 26.6.1 stack with TESTSIGNING enabled.
Running the install path now would not produce a clean no-binary-modification proof.

## Manual E2E sequence

```powershell
# 1. Disable TESTSIGNING and reboot
.\Tools\Disable-TestSigning.ps1

# 2. After reboot, confirm anchor baseline or install anchor first
.\Tools\Test-Anchor-Status.ps1

# 3. Run hybrid install test (admin)
.\Tools\Test-Whql-Hybrid-26.6.1-25.2.1.ps1 `
  -SoftwareSourceRoot "C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF" `
  -KernelSourceRoot "C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF"

# 4. After reboot, resume
.\Tools\Test-Whql-Hybrid-26.6.1-25.2.1.ps1 -ResumeAfterReboot

# 5. Optional rollback drill without corrupting binaries
.\Tools\Test-Whql-Hybrid-26.6.1-25.2.1.ps1 -TestRollbackAfterInstall

# 6. Archive diagnostics
.\Tools\Capture-Driver-Diagnostics.ps1
```

## Pass criteria reminder

- TESTSIGNING remains OFF
- problem code `0`
- driver version `32.0.21043.12001`
- loaded kernel SHA `E04E8054…`
- loaded UMD SHA `93927BB0…`
- loaded GCF SHA `D1AC965F…`
- rollback restores anchor version `32.0.12033.5029`

WHQL-link/dxdiag checks are diagnostic only and must not be treated as Microsoft WHQL
certification evidence.
