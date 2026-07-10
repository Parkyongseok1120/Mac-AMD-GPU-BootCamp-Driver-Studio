# Official channel backlog

This is an external follow-up list for paths that cannot be completed locally with
official AMD package bytes unchanged.

## AMD support request (updated 2026-07-10 for 26.6.4)

Ask AMD whether Boot Camp hardware `PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`
can be supported in official Adrenalin packages **without** local binary modification.

**26.6.4 evidence to attach:**

- Phase 0 static analysis: `docs/26.6.4-vs-26.6.1-AMDGCF-DIFF.md`
- INF `ExcludeID` for `020F106B` still present (3 occurrences in `u0202073.inf`)
- `amdgcf.dat` entry count still `170`, no `407340` / `020F106B` records
- AMDGCF failure string still in `amdkmdag.sys`, gate byte `0x79` at `0x52A9F`
- Raw log: `C:\AMD\amdgcf-binary-diff-26.6.4.txt`

Needed from AMD:

- Official `amdgcf.dat` entry for `020F106B` in a current WHQL branch, or
- INF/hardware-support update that makes the original 26.6.x kernel accept the device without AMDGCF failure, or
- An official Boot Camp package newer than Apple 21.30.45.22 (August 2025)

References:

- [AMD 26.6.4 release notes](https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-26-6-4.html) — Boot Camp not listed
- [AMD 26.6.1 release notes](https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-26-6-1.html) — same Boot Camp exclusion

### Draft support request text

> We are validating Boot Camp support for MacBook Pro 16-inch 2019 Radeon Pro 5500M
> (`PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`) on Windows 10/11 without modifying
> AMD driver binaries. AMD 26.6.4 WHQL (`32.0.21043.19003`) still excludes this hardware ID
> in INF and lacks the Boot Camp record in `amdgcf.dat`. The 26.6.4 kernel retains the AMDGCF
> runtime gate that blocks INF-only installation. Can AMD provide official Boot Camp support
> for this hardware in a current WHQL package, or confirm whether a 25.2.1-class kernel with
> 26.6.4 user-mode components is a supported configuration?

## Microsoft attestation / WHQL

Investigate whether a changed INF with unchanged driver binaries can receive a
Microsoft-trusted replacement catalog for Secure Boot distribution.

Workflow: `docs/MS-ATTESTATION-SUBMISSION.md`  
Export tool: `Tools/Export-AttestationPackage.ps1`

Important limits from local analysis:

- Microsoft signing can make a modified INF installable under TESTSIGNING OFF
- It cannot change the 26.6.x kernel runtime AMDGCF rejection documented in
  `docs/26.6.1-INF-ONLY-BLOCKER.md` and `docs/26.6.4-vs-26.6.1-AMDGCF-DIFF.md`
- Hybrid path substitutes the **25.2.1 WHQL kernel** to avoid the 26.6.x AMDGCF gate

Local result (2026-07-10): self-signed hybrid catalog → `0xC0000428`. Attestation required.

Reference: [Microsoft catalog files](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/catalog-files)

## Apple Boot Camp legacy packages

Check whether Apple-distributed Boot Camp AMD packages contain a Boot Camp-specific
`amdgcf.dat` record or INF support that never appeared in public Adrenalin packages.

### Investigation checklist

| Step | Action |
|---|---|
| 1 | Obtain Apple Boot Camp 6.x driver pack for 2019 16-inch MacBook Pro (latest: 21.30.45.22, August 2025) |
| 2 | Extract AMD display package and locate `amdgcf.dat` |
| 3 | Search for `020F106B`, `407340`, entry count vs 26.6.4 (`170`) |
| 4 | Compare INF hardware IDs and `ExcludeID` entries |
| 5 | Record kernel `amdkmdag.sys` SHA — does Apple ship 25.2.1-class or older kernel? |
| 6 | Document whether Apple GCF entry can inform an official AMD request (not for redistribution) |

Tool: `Tools/Compare-AmdgcfBinaries.ps1` (adapt labels for Apple vs 26.6.4)

## Current local recommendation

Until an official AMD package or MS-signed hybrid exists:

1. Use `whql-anchor` 25.2.1 as the stable no-binary-modification release (**Verified**)
2. Treat `original-kernel-hybrid` 26.6.4 as **Experimental** — prepare/verify only
3. Do **not** install local-signed hybrid under TESTSIGNING OFF
4. Keep `legacy-binary-patch` hidden from normal UI
