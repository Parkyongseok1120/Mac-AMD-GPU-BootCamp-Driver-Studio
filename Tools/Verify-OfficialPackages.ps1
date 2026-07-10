#Requires -Version 5.1

param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ProfilePath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'Profiles\radeon-pro-5500m-original-kernel-hybrid-26.6.4.json'),
    [string]$SoftwareSourceRoot = 'C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF',
    [string]$KernelSourceRoot = 'C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF',
    [string]$ResultPath = 'C:\AMD\official-package-verification.txt'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

$profileFullPath = if ([IO.Path]::IsPathRooted($ProfilePath)) { $ProfilePath } else { Join-Path $ProjectRoot $ProfilePath }
$anchorProfilePath = Join-Path $ProjectRoot 'Profiles\radeon-pro-5500m-whql-anchor-25.2.1.json'
$hybrid = Get-Content -LiteralPath $profileFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
$anchor = Get-Content -LiteralPath $anchorProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$result = [System.Collections.Generic.List[string]]::new()

function Add-Result([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $result.Add($line)
    Write-Host $line
}

function Assert-ProfileFile([string]$Root, $Rule, [string]$Label) {
    $path = Join-Path $Root (($Rule.path -replace '/', '\'))
    if (-not (Test-Path -LiteralPath $path)) { throw "$Label missing: $($Rule.path)" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actual -ne [string]$Rule.sha256) {
        throw "$Label hash mismatch for $($Rule.path). Expected=$($Rule.sha256) Actual=$actual"
    }
    Add-Result "HASH_OK $Label/$($Rule.path)=$actual"
}

try {
    Add-Result "PROFILE=$($hybrid.id)"
    Add-Result "SOFTWARE_ROOT=$SoftwareSourceRoot"
    Add-Result "KERNEL_ROOT=$KernelSourceRoot"

    foreach ($rule in $hybrid.files) {
        Assert-ProfileFile $SoftwareSourceRoot $rule $hybrid.marketingVersion
    }

    foreach ($rule in $anchor.files) {
        Assert-ProfileFile $KernelSourceRoot $rule '25.2.1'
    }

    foreach ($source in $hybrid.additionalSources) {
        foreach ($rule in $source.files) {
            Assert-ProfileFile $KernelSourceRoot $rule $source.displayName
        }
    }

    Add-Result 'PACKAGE_VERIFICATION=PASS'
    [IO.File]::WriteAllLines($ResultPath, $result, (New-Object Text.UTF8Encoding($false)))
    exit 0
}
catch {
    Add-Result "ERROR: $($_.Exception.Message)"
    [IO.File]::WriteAllLines($ResultPath, $result, (New-Object Text.UTF8Encoding($false)))
    exit 1
}
