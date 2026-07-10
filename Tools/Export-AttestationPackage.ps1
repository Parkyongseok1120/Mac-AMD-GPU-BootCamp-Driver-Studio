#Requires -RunAsAdministrator

param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ProfilePath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'Profiles\radeon-pro-5500m-original-kernel-hybrid-26.6.4.json'),
    [string]$SoftwareSourceRoot = 'C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF',
    [string]$KernelSourceRoot = 'C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF',
    [string]$OutputRoot = 'C:\AMD\attestation',
    [string]$PackageZip = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

$profileFullPath = if ([IO.Path]::IsPathRooted($ProfilePath)) { $ProfilePath } else { Join-Path $ProjectRoot $ProfilePath }
$profile = Get-Content -LiteralPath $profileFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
$marketingVersion = [string]$profile.marketingVersion
$slug = $marketingVersion -replace '\.', ''
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$exportRoot = Join-Path $OutputRoot "hybrid-$slug-$stamp"
$manifestPath = Join-Path $exportRoot 'file-hash-manifest.json'
$checklistPath = Join-Path $exportRoot 'SUBMISSION-CHECKLIST.md'
$evidencePath = Join-Path $exportRoot 'source-package-evidence.txt'
$prepResultPath = Join-Path $exportRoot 'prepare-result.txt'
if (-not $PackageZip) { $PackageZip = Join-Path $OutputRoot "attestation-hybrid-$slug-$stamp.zip" }

function Get-FileHashRecord([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Label missing: $Path" }
    return [pscustomobject]@{
        label = $Label
        path = $Path
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        size = (Get-Item -LiteralPath $Path).Length
    }
}

New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null

& (Join-Path $PSScriptRoot 'Test-Whql-Hybrid.ps1') `
    -ProjectRoot $ProjectRoot `
    -ProfilePath $profileFullPath `
    -SoftwareSourceRoot $SoftwareSourceRoot `
    -KernelSourceRoot $KernelSourceRoot `
    -ResultPath $prepResultPath `
    -PrepareOnly `
    -SkipCatalogSigning

$prepLines = Get-Content -LiteralPath $prepResultPath -Encoding UTF8
$prepareRootLine = $prepLines | Where-Object { $_ -match 'PREPARE_ONLY_ROOT=' } | Select-Object -Last 1
if (-not $prepareRootLine) { throw 'Prepare step did not report PREPARE_ONLY_ROOT.' }
$prepareRoot = ($prepareRootLine -split '=', 2)[1].Trim()
if (-not (Test-Path -LiteralPath $prepareRoot)) { throw "Prepared package missing: $prepareRoot" }

$records = [System.Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $prepareRoot -Recurse -File) {
    $relative = $file.FullName.Substring($prepareRoot.TrimEnd('\').Length + 1)
    $records.Add([pscustomobject]@{
        relativePath = $relative
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        size = $file.Length
    })
}

$manifest = [pscustomobject]@{
    generatedAt = (Get-Date).ToString('o')
    profileId = [string]$profile.id
    driverVersion = [string]$profile.driverVersion
    marketingVersion = $marketingVersion
    preparedRoot = $prepareRoot
    catalogSigning = 'skipped_for_attestation'
    files = $records
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$evidence = [System.Collections.Generic.List[string]]::new()
$evidence.Add("Attestation source evidence generated $($manifest.generatedAt)")
$evidence.Add("Profile=$($profile.id)")
$evidence.Add("PreparedRoot=$prepareRoot")
$evidence.Add('')
$evidence.Add('=== 26.6.x software package (original WHQL bytes) ===')
foreach ($rule in $profile.files) {
    $path = Join-Path $SoftwareSourceRoot (($rule.path -replace '/', '\'))
    $record = Get-FileHashRecord $path "software/$($rule.path)"
    $evidence.Add("$($record.label) sha256=$($record.sha256) size=$($record.size)")
}
$evidence.Add('')
$evidence.Add('=== 25.2.1 kernel anchor (original WHQL bytes) ===')
foreach ($source in $profile.additionalSources) {
    foreach ($rule in $source.files) {
        $path = Join-Path $KernelSourceRoot (($rule.path -replace '/', '\'))
        $record = Get-FileHashRecord $path "$($source.id)/$($rule.path)"
        $evidence.Add("$($record.label) sha256=$($record.sha256) size=$($record.size)")
    }
}
$evidence.Add('')
$evidence.Add('=== Patched INF expectation ===')
$infRule = $profile.files | Where-Object { $_.path -eq $profile.infName } | Select-Object -First 1
$patchedInf = Join-Path $prepareRoot ([string]$profile.infName)
$patchedActual = (Get-FileHash -LiteralPath $patchedInf -Algorithm SHA256).Hash
$evidence.Add("patched:$($profile.infName) expected=$($infRule.patchedSha256) actual=$patchedActual")
if ($patchedActual -ne [string]$infRule.patchedSha256) { throw 'Patched INF hash mismatch in prepared package.' }
[IO.File]::WriteAllLines($evidencePath, $evidence, (New-Object Text.UTF8Encoding($false)))

$checklist = @(
    '# Microsoft Hardware Dev Center attestation checklist',
    '',
    "Profile: ``$($profile.id)``",
    "Target driver version: ``$($profile.driverVersion)``",
    "Prepared package: ``$prepareRoot``",
    '',
    '## Package contents',
    '',
    '- [ ] Modified INF only (`u0202073.inf` for 26.6.4) — Boot Camp hardware ID added, ExcludeID commented',
    '- [ ] 26.6.4 UMD binaries unchanged (`amdxx64.dll`, `amdgcf.dat`, all other Display2 files)',
    '- [ ] 25.2.1 WHQL kernel substituted (`amdkmdag.sys` = `E04E8054…`) — byte-for-byte from anchor package',
    '- [ ] No `SYS`/`DLL`/`DAT` edits beyond the approved kernel file copy from 25.2.1',
    '- [ ] `file-hash-manifest.json` attached',
    '- [ ] `source-package-evidence.txt` attached',
    '- [ ] `docs/26.6.4-vs-26.6.1-AMDGCF-DIFF.md` attached as blocker evidence',
    '- [ ] `docs/HYBRID-E2E-VALIDATION.md` local-sign failure (`0xC0000428`) attached',
    '',
    '## Submission notes for Microsoft',
    '',
    '- INF modification adds Boot Camp MacBook Pro 2019 Radeon Pro 5500M (`SUBSYS_020F106B`).',
    '- Original 26.6.4 kernel is replaced with the 25.2.1 WHQL kernel because 26.6.4 INF-only fails AMDGCF gate.',
    '- All non-kernel binaries remain original AMD 26.6.4 WHQL bytes.',
    '- Request attestation-signed replacement catalog for `amdgpu.cat`.',
    '',
    '## Post-submission E2E',
    '',
    '```powershell',
    ".\Tools\Test-Whql-Hybrid-MsSigned.ps1 -MsSignedCatalogPath `"C:\AMD\attestation\amdgpu.cat`"",
    '.\Tools\Test-Whql-Hybrid-MsSigned.ps1 -ResumeAfterReboot',
    '```',
    '',
    'See `docs/MS-ATTESTATION-SUBMISSION.md` for the full workflow.'
)
[IO.File]::WriteAllLines($checklistPath, $checklist, (New-Object Text.UTF8Encoding($false)))

$stagingRoot = Join-Path $exportRoot 'package'
if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
Copy-Item -LiteralPath $prepareRoot -Destination $stagingRoot -Recurse
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $stagingRoot 'file-hash-manifest.json')
Copy-Item -LiteralPath $evidencePath -Destination (Join-Path $stagingRoot 'source-package-evidence.txt')
Copy-Item -LiteralPath $checklistPath -Destination (Join-Path $stagingRoot 'SUBMISSION-CHECKLIST.md')
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'docs\26.6.4-vs-26.6.1-AMDGCF-DIFF.md') -Destination (Join-Path $stagingRoot '26.6.4-vs-26.6.1-AMDGCF-DIFF.md') -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'docs\HYBRID-E2E-VALIDATION.md') -Destination (Join-Path $stagingRoot 'HYBRID-E2E-VALIDATION.md') -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $PackageZip) { Remove-Item -LiteralPath $PackageZip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stagingRoot, $PackageZip)

Write-Host "EXPORT_ROOT=$exportRoot"
Write-Host "PREPARED_ROOT=$prepareRoot"
Write-Host "MANIFEST=$manifestPath"
Write-Host "CHECKLIST=$checklistPath"
Write-Host "PACKAGE_ZIP=$PackageZip"
exit 0
