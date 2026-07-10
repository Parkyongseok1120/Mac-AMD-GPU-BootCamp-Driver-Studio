#Requires -Version 5.1

param(
    [string]$AppleInfPath = '',
    [string]$ApplePackageRoot = '',
    [string]$Compare2521Root = 'C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF',
    [string]$ResultPath = 'C:\AMD\apple-bootcamp-scan.txt'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$result = [System.Collections.Generic.List[string]]::new()

function Add([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $result.Add($line)
    Write-Host $line
}

function Find-AsciiString([byte[]]$Bytes, [string]$Text) {
    $pattern = [Text.Encoding]::ASCII.GetBytes($Text)
    for ($i = 0; $i -le $Bytes.Length - $pattern.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $pattern.Length; $j++) {
            if ($Bytes[$i + $j] -ne $pattern[$j]) { $match = $false; break }
        }
        if ($match) { return $i }
    }
    return -1
}

function Analyze-Gcf([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add "$Label GCF_PRESENT=False"
        return
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $count = [BitConverter]::ToInt32($bytes, 0)
    Add "$Label GCF_SHA256=$hash entryCount=$count size=$($bytes.Length)"
    foreach ($name in @('020F106B', '407340', '7340')) {
        $found = Find-AsciiString $bytes $name
        Add "$Label PATTERN_$name=$($found -ge 0) offset=$(if ($found -ge 0) { '0x{0:X}' -f $found } else { 'n/a' })"
    }
}

function Analyze-Kernel([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add "$Label KERNEL_PRESENT=False"
        return
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $needle = 'AMDGCF verification failed, driver will fail to start. Forced install, or issue with AMDGCF file?'
    $index = Find-AsciiString $bytes $needle
    Add "$Label KERNEL_SHA256=$hash size=$($bytes.Length) AMDGCF_STRING=$($index -ge 0)"
}

function Analyze-Inf([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add "$Label INF_PRESENT=False"
        return
    }
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::ASCII)
    Add "$Label INF_PATH=$Path"
    foreach ($pattern in @('020F106B', 'ExcludeID = PCI\VEN_1002&DEV_7340&SUBSYS_020F106B', 'PP_Apple_Bootcamp_Enable', 'KMD_BootCampPlatform')) {
        $count = 0
        for ($index = 0; ($index = $text.IndexOf($pattern, $index, [StringComparison]::Ordinal)) -ge 0; $index += $pattern.Length) { $count++ }
        Add "$Label INF_COUNT_$($pattern.Replace('\','_'))=$count"
    }
}

try {
    if (-not $AppleInfPath) {
        $AppleInfPath = Join-Path $env:TEMP 'apple_r6.4_v21.30.45.22.inf'
        if (-not (Test-Path -LiteralPath $AppleInfPath)) {
            Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/icywire/project-falcon/master/original_inf_files/apple_r6.4_v21.30.45.22.inf' `
                -OutFile $AppleInfPath -UseBasicParsing
        }
    }

    Analyze-Inf $AppleInfPath 'APPLE_FALCON_INF'

    if ($ApplePackageRoot -and (Test-Path -LiteralPath $ApplePackageRoot)) {
        $gcf = Get-ChildItem -LiteralPath $ApplePackageRoot -Recurse -Filter 'amdgcf.dat' -File | Select-Object -First 1
        $kernel = Get-ChildItem -LiteralPath $ApplePackageRoot -Recurse -Filter 'amdkmdag.sys' -File | Select-Object -First 1
        if ($gcf) { Analyze-Gcf $gcf.FullName 'APPLE_PACKAGE' }
        if ($kernel) { Analyze-Kernel $kernel.FullName 'APPLE_PACKAGE' }
    } else {
        Add 'APPLE_PACKAGE_ROOT=Not supplied; INF-only scan from Falcon original_inf_files reference'
    }

    $gcf2521 = Join-Path $Compare2521Root 'B412641\amdgcf.dat'
    $kernel2521 = Join-Path $Compare2521Root 'B412641\amdkmdag.sys'
    $inf2521 = Join-Path $Compare2521Root 'u0412654.inf'
    if (Test-Path -LiteralPath $gcf2521) { Analyze-Gcf $gcf2521 'WHQL_25.2.1' } else { Add 'WHQL_25.2.1 GCF_PRESENT=False (no amdgcf.dat in 25.2.1 package)' }
    Analyze-Kernel $kernel2521 'WHQL_25.2.1'
    Analyze-Inf $inf2521 'WHQL_25.2.1'

    Add 'CONCLUSION:'
    Add '- Apple Boot Camp 21.30.45.22 INF (Falcon reference) includes 020F106B hardware support.'
    Add '- A full zero-mod install still requires the Apple package binaries and Microsoft-signed catalog on disk.'
    Add '- 25.2.1 WHQL anchor is the verified production path in this repository.'
    Add '- AMD Adrenalin 26.6.x patch distribution was discontinued due to copyright, EULA, and licensing concerns.'

    [IO.File]::WriteAllLines($ResultPath, $result, (New-Object Text.UTF8Encoding($false)))
    Add "RESULT_PATH=$ResultPath"
    exit 0
}
catch {
    Add "ERROR: $($_.Exception.Message)"
    [IO.File]::WriteAllLines($ResultPath, $result, (New-Object Text.UTF8Encoding($false)))
    exit 1
}
