# Official channel backlog

External follow-up items that cannot be completed locally with official AMD package bytes unchanged.

## Current recommendation (2026-07-11)

Use the **25.2.1 WHQL anchor** profile as the only supported release path for Radeon Pro 5500M Boot Camp.

## 26.6.x discontinuation notice

**Due to copyright, EULA, and related licensing concerns, 26.6.x patch distribution has been discontinued in this repository.**

AMD Adrenalin 26.6.1 and 26.6.4 profiles, hybrid recipes, attestation experiments, and binary-patch workflows have been removed and will not be maintained here. Users must download official AMD installers directly from AMD and comply with AMD's license terms.

Prior technical findings (for historical context only):

- INF-only and kernel-hybrid recipes failed on target hardware without binary patching
- 25.2.1 kernel + 26.6.4 UMD hybrid failed with `STATUS_DEVICE_CONFIGURATION_ERROR` even after full kernel-data matching
- Microsoft attestation cannot fix UMD–KMD compatibility; it only changes catalog trust

## AMD support request (optional)

Ask AMD whether Boot Camp hardware `PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40` can be supported in official Adrenalin packages without local binary modification.

Needed from AMD:

- Official `amdgcf.dat` entry for `020F106B` in a current WHQL branch, or
- INF/hardware-support update that accepts the device without AMDGCF failure, or
- An official Boot Camp package newer than Apple 21.30.45.22 (August 2025)

References:

- [AMD 25.2.1 release notes](https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-25-2-1.html)
- Apple Boot Camp scan: `docs/APPLE-BOOTCAMP-SCAN.md`

## Apple Boot Camp scan status

INF reference scan complete — see `docs/APPLE-BOOTCAMP-SCAN.md`

Tool: `Tools/Scan-AppleBootCamp.ps1`
