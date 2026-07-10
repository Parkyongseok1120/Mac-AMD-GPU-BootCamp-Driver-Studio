# 26.6.x no-binary-patch validation

## Scope

The no-binary-patch recipes must never edit a driver `SYS`, `DLL`, or `DAT` file.
Changing the INF and generating a replacement catalog are tracked separately: they do not alter a
driver binary, but they invalidate AMD's original package catalog and therefore are not equivalent
to an original WHQL package.

## Recipes

| Mode | UMD stack | Kernel | TESTSIGNING | Release status |
|---|---|---|---:|---|
| `inf-only` | Original 26.6.x | Original 26.6.x | Off target | Fails on target hardware — AMDGCF gate in kernel, no Boot Camp `020F106B` in `amdgcf.dat`. Confirmed for 26.6.1 and 26.6.4. |
| `original-kernel-hybrid` | 26.6.4 user-mode files plus an original 25.2.1 kernel | Original 25.2.1 | Off target | **Primary target.** Offline prepare/self-test PASS. Hardware E2E with **local** catalog **failed** (`0xC0000428`, 2026-07-10). Requires **Microsoft attestation catalog**. |
| `legacy-binary-patch` | Modified | Modified 26.6.x | On | Legacy only; hidden from normal UI. Do not use for new validation work. |

The hybrid profile explicitly verifies the original 25.2.1 kernel SHA-256 before copying it. It must
never be presented as proof that the original 26.6.x kernel works without a binary patch.

## 26.6.4 as primary target

AMD 26.6.4 WHQL (`32.0.21043.19003`) supersedes 26.6.1 as the mandatory UMD target. Phase 0 static
analysis shows identical Boot Camp blockers:

- INF `ExcludeID` for `020F106B` (3 occurrences)
- `amdgcf.dat` entry count `170`, no `407340` / `020F106B` records
- AMDGCF failure string in `amdkmdag.sys`, gate byte `0x79` at `0x52A9F`

Profile: `Profiles/radeon-pro-5500m-original-kernel-hybrid-26.6.4.json`

## Local signing result (2026-07-10)

| Attempt | Catalog signer | TESTSIGNING | Result |
|---|---|---|---|
| 26.6.1 hybrid E2E | `CN=Local AMD BootCamp Test Driver` | OFF | **FAIL** — CODE=31, `0xC0000428` after reboot |
| Rollback | n/a | OFF | **PASS** — restored `32.0.12033.5029`, CODE=0 |

**Conclusion:** A locally signed hybrid catalog cannot be used for TESTSIGNING OFF distribution.
`Tools/Test-Whql-Hybrid.ps1` blocks this path unless `-AllowLocalCatalogSigning` is explicitly set.

## Required evidence before release

1. The source packages match every profile SHA-256 rule.
2. The prepared package satisfies every runtime-file assertion. For `inf-only`, this proves that the
   26.6.x kernel and configuration data are unchanged. For `original-kernel-hybrid`, it proves that
   the copied 25.2.1 kernel is byte-for-byte original.
3. After a cold reboot, `TESTSIGNING` is off, Device Manager reports problem code `0`, and the
   target driver version (`32.0.21043.19003` for 26.6.4 hybrid) is active.
4. A failed installation restores the exported OEM driver automatically.
5. Repeat the test on a clean target installation before changing the profile beyond
   `Experimental`. Use `Tools/Test-Hybrid-Clean-Install.ps1` as the checklist and keep the hybrid
   profile at `Experimental` or `Community Verified` only after independent replication.

## Distribution gate

A package with a changed INF cannot retain AMD's original catalog signature. A normal-user release
with Secure Boot enabled therefore requires a Microsoft-trusted replacement catalog and the rights
to submit the package through Hardware Dev Center attestation.

Do not label an experimental locally signed package as a public or WHQL release.

Submission workflow: `docs/MS-ATTESTATION-SUBMISSION.md`  
Export tool: `Tools/Export-AttestationPackage.ps1`
