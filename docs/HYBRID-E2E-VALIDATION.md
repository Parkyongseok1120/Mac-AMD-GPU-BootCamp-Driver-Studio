# Hybrid E2E validation log



Date: 2026-07-10  

Target: MacBook Pro 16-inch 2019, Radeon Pro 5500M (`PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`)



## Completed offline checks



| Step | Tool | Result |

|---|---|---|

| Official package SHA verification | `Tools/Verify-OfficialPackages.ps1` | PASS |

| 26.6.1 hybrid package preparation | `Tools/Test-Whql-Hybrid-26.6.1-25.2.1.ps1 -PrepareOnly` | PASS |

| 26.6.4 hybrid package preparation | `Tools/Test-Whql-Hybrid.ps1 -PrepareOnly` | PASS (profile `amd-26.6.4-radeon-pro-5500m-020f106b-original-kernel-hybrid`) |

| App/profile pipeline | `Tools/ProfileSelfTest/ProfileSelfTest.csproj` | `SELF_TEST=PASS` |

| 26.6.1 runtime assertions | prepared hybrid package | kernel `E04E8054…`, UMD `93927BB0…`, GCF `D1AC965F…` |

| 26.6.4 runtime assertions | prepared hybrid package | kernel `E04E8054…`, UMD `43D9ADA5…`, GCF `E79E42B8…` |



Prepared package examples:



- `C:\AMD\BootCampDriverStudio\Prepared\AMD-26.6.1-with-25.2.1-kernel-20260710-174038`

- `C:\AMD\BootCampDriverStudio\Prepared\AMD-26.6.4-with-25.2.1-kernel-<stamp>`



## Anchor baseline (post-rollback, 2026-07-10)



Captured after the failed 26.6.1 hybrid attempt and successful rollback:



| Check | Value |

|---|---|

| GPU problem code | `0` |

| Driver version | `32.0.12033.5029` |

| TESTSIGNING | **OFF** |

| Anchor-ready baseline | **True** |



## 26.6.1 hybrid hardware E2E — FAIL (2026-07-10)



Environment: TESTSIGNING OFF, 25.2.1 WHQL anchor active (`32.0.12033.5029`, CODE=0).



| Step | Result |

|---|---|

| Script install (`Test-Whql-Hybrid-26.6.1-25.2.1.ps1`) | `HYBRID_INSTALL_EXIT=1` — `pnputil` argument parsing bug (usage screen) |

| Manual `pnputil /add-driver <prepared INF> /install` | Exit `3010` (reboot pending) |

| Post-reboot verification | **FAIL** — CODE=`31`, NTSTATUS `0xC0000428` |

| Active driver version after failure | `32.0.21043.12001` |

| Active INF | `oem73.inf` |

| Rollback to 25.2.1 anchor | **PASS** — `32.0.12033.5029`, CODE=0 |



### Root cause



The prepared hybrid package file hashes were correct, but the locally signed `amdgpu.cat`

(`CN=Local AMD BootCamp Test Driver`) is rejected under TESTSIGNING OFF. Windows loads the

driver package and then fails signature validation with `0xC0000428`.



This is a **catalog trust** failure, not an AMDGCF runtime gate failure. The INF-only

blocker still applies if the original 26.6.4 kernel is used; the hybrid path avoids that by

substituting the original 25.2.1 WHQL kernel.



### Policy change



`Tools/Test-Whql-Hybrid.ps1` now blocks hybrid installation when:



- TESTSIGNING is OFF, and

- the catalog signer is the local test certificate, and

- `-AllowLocalCatalogSigning` is not set



Use `-MsSignedCatalogPath` with a Microsoft Hardware Dev Center attestation catalog for

production E2E, or `-AllowLocalCatalogSigning` only for deliberate experimental installs

with TESTSIGNING ON.



## 26.6.4 target status



Phase 0 static analysis confirms 26.6.4 has the **same Boot Camp blockers** as 26.6.1.

INF-only 26.6.4 is not viable. The mandatory path is:



**26.6.4 UMD + 25.2.1 WHQL kernel hybrid + Microsoft-trusted attestation catalog**



See `docs/26.6.4-vs-26.6.1-AMDGCF-DIFF.md` and `docs/MS-ATTESTATION-SUBMISSION.md`.



## Manual E2E sequence (26.6.4, MS-signed catalog)



```powershell

# 1. Confirm anchor baseline

.\Tools\Test-Anchor-Status.ps1



# 2. Export attestation package (unsigned catalog, for Hardware Dev Center)

.\Tools\Export-AttestationPackage.ps1



# 3. After Microsoft returns attestation-signed amdgpu.cat:

.\Tools\Test-Whql-Hybrid-MsSigned.ps1 `

  -MsSignedCatalogPath "C:\AMD\attestation\amdgpu.cat" `

  -SoftwareSourceRoot "C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF" `

  -KernelSourceRoot "C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF"



# 4. After reboot, resume

.\Tools\Test-Whql-Hybrid-MsSigned.ps1 -ResumeAfterReboot



# 5. Archive diagnostics

.\Tools\Capture-Driver-Diagnostics.ps1

```



Legacy 26.6.1 wrapper remains at `Tools/Test-Whql-Hybrid-26.6.1-25.2.1.ps1` for regression

comparison only.



## 26.6.4 MS-signed hybrid E2E — BLOCKED (pending attestation)

| Prerequisite | Status |
|---|---|
| Attestation package export | **Ready** — `C:\AMD\attestation\attestation-hybrid-2664-*.zip` |
| Microsoft-signed `amdgpu.cat` | **Not received** — Hardware Dev Center submission required |
| E2E script | **Ready** — `Tools/Test-Whql-Hybrid-MsSigned.ps1` |

Run after Microsoft returns the attestation-signed catalog. Until then, do not attempt
local-signed hybrid install under TESTSIGNING OFF.

## Pass criteria (26.6.4 hybrid, MS-signed)



- TESTSIGNING remains OFF

- problem code `0`

- driver version `32.0.21043.19003`

- loaded kernel SHA `E04E8054…` (25.2.1 original)

- loaded UMD SHA `43D9ADA5…` (26.6.4 original)

- loaded GCF SHA `E79E42B8…` (26.6.4 original)

- rollback restores anchor version `32.0.12033.5029`



WHQL-link/dxdiag checks are diagnostic only and must not be treated as Microsoft WHQL

certification evidence.

