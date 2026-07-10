# 26.6.1 no-binary-patch validation

## Scope

The no-binary-patch recipes must never edit a driver `SYS`, `DLL`, or `DAT` file.
Changing the INF and generating a replacement catalog are tracked separately: they do not alter a
driver binary, but they invalidate AMD's original package catalog and therefore are not equivalent
to an original WHQL package.

## Recipes

| Mode | 26.6.1 files | Kernel | TESTSIGNING | Release status |
|---|---|---|---:|---|
| `inf-only` | Original | Original 26.6.1 | Off target | The only 26.6.1 candidate. Experimental; currently known to fail after boot on the target hardware. |
| `original-kernel-hybrid` | 26.6.1 user-mode files plus an original 25.2.1 kernel | Original 25.2.1 | Off target | Experimental. Offline prepare/self-test PASS on 2026-07-10; hardware E2E pending anchor baseline and TESTSIGNING OFF. |
| `legacy-binary-patch` | Modified | Modified 26.6.1 | On | Legacy only; hidden from normal UI. Do not use for new validation work. |

The hybrid profile explicitly verifies the original 25.2.1 kernel SHA-256 before copying it. It must
never be presented as proof that the original 26.6.1 kernel works without a binary patch.

## Required evidence before release

1. The source packages match every profile SHA-256 rule.
2. The prepared package satisfies every runtime-file assertion. For `inf-only`, this proves that the
   26.6.1 kernel and configuration data are unchanged. For `original-kernel-hybrid`, it proves that
   the copied 25.2.1 kernel is byte-for-byte original.
3. After a cold reboot, `TESTSIGNING` is off, Device Manager reports problem code `0`, and the
   target driver version is active.
4. A failed installation restores the exported OEM driver automatically.
5. Repeat the test on a clean target installation before changing the profile beyond
   `Experimental`. Use `Tools/Test-Hybrid-Clean-Install.ps1` as the checklist and keep the hybrid
   profile at `Experimental` or `Community Verified` only after independent replication.

## Distribution gate

A package with a changed INF cannot retain AMD's original catalog signature. A normal-user release
with Secure Boot enabled therefore requires a Microsoft-trusted replacement catalog and the rights
to submit the package. Do not label an experimental locally signed package as a public or WHQL
release.
