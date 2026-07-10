#Requires -Version 5.1

param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ProfilePath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'Profiles\radeon-pro-5500m-whql-anchor-25.2.1.json'),
    [string]$SourceRoot = 'C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF',
    [string]$ResultPath = 'C:\AMD\official-package-verification.txt'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

$profileFullPath = if ([IO.Path]::IsPathRooted($ProfilePath)) { $ProfilePath } else { Join-Path $ProjectRoot $ProfilePath }
$profile = Get-Content -LiteralPath $profileFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
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
    Add-Result "PROFILE=$($profile.id)"
    Add-Result "SOURCE_ROOT=$SourceRoot"

    foreach ($rule in $profile.files) {
        Assert-ProfileFile $SourceRoot $rule $profile.marketingVersion
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
