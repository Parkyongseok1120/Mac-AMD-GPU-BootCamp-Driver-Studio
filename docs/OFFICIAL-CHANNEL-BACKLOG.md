# Official channel backlog

This is an external follow-up list for paths that cannot be completed locally with
official AMD package bytes unchanged.

## AMD support request

Ask AMD whether Boot Camp hardware `PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40`
can be supported in an official 26.6.1 package without local binary modification.

Needed from AMD:

- Official `amdgcf.dat` entry for `020F106B`
- Or an INF/hardware-support update that makes the original 26.6.1 kernel accept the
  device without internal AMDGCF failure

Reference: [AMD 26.6.1 release notes](https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-26-6-1.html)

## Microsoft attestation / WHQL

Investigate whether a changed INF with unchanged driver binaries can receive a
Microsoft-trusted replacement catalog for Secure Boot distribution.

Important limit from local analysis:

- Microsoft signing can make a modified INF installable
- It cannot change the 26.6.1 kernel runtime AMDGCF rejection documented in
  `docs/26.6.1-INF-ONLY-BLOCKER.md`

Reference: [Microsoft catalog files](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/catalog-files)

## Apple Boot Camp legacy packages

Check whether Apple-distributed Boot Camp AMD packages contain a Boot Camp-specific
`amdgcf.dat` record or INF support that never appeared in public Adrenalin packages.

## Current local recommendation

Until an official AMD package exists:

1. Use `whql-anchor` 25.2.1 as the stable no-binary-modification release
2. Treat `original-kernel-hybrid` as Experimental
3. Keep `legacy-binary-patch` hidden from normal UI
