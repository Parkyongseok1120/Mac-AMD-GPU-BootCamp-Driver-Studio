# Apple Boot Camp scan

Reference scan for Apple Boot Camp driver packages vs the 25.2.1 WHQL anchor path.

## Key finding

Apple `apple_r6.4_v21.30.45.22.inf` (via Falcon `original_inf_files`) includes `020F106B` with no ExcludeID.

This supports an optional AMD support request but does **not** replace the verified 25.2.1 WHQL anchor workflow in this repository.

## Comparison summary

| Item | Apple `apple_r6.4_v21.30.45.22.inf` | 25.2.1 WHQL `u0412654.inf` |
|---|---|---|
| `020F106B` device ID | Present | Excluded (patched by anchor profile) |
| ExcludeID for Boot Camp | None | Present until profile patch |
| MS-signed catalog | Yes (Apple package) | Yes (AMD WHQL) |

## Tool

`Tools/Scan-AppleBootCamp.ps1`

## Current recommendation

Use the 25.2.1 WHQL anchor profile. AMD Adrenalin 26.6.x patch workflows were discontinued due to copyright, EULA, and licensing concerns — see `docs/OFFICIAL-CHANNEL-BACKLOG.md`.
