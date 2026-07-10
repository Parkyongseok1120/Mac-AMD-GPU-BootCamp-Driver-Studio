#Requires -Version 5.1

param(
    [string]$Kernel2661 = 'C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF\B026079\amdkmdag.sys',
    [string]$Kernel2521 = 'C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF\B412641\amdkmdag.sys',
    [string]$Gcf2661 = 'C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF\B026079\amdgcf.dat',
    [string]$ResultPath = 'C:\AMD\amdgcf-binary-diff.txt'
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

function Format-HexContext([byte[]]$Bytes, [int]$Offset, [int]$Before = 8, [int]$After = 8) {
    $start = [Math]::Max(0, $Offset - $Before)
    $end = [Math]::Min($Bytes.Length - 1, $Offset + $After)
    $slice = $Bytes[$start..$end]
    $hex = ($slice | ForEach-Object { $_.ToString('X2') }) -join ' '
    return "offset=0x{0:X} context={1}" -f $Offset, $hex
}

function Analyze-Kernel([string]$Path, [string]$Label, [int]$KnownGateOffset = -1) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    Add "$Label SHA256=$hash size=$($bytes.Length)"
    $needle = 'AMDGCF verification failed, driver will fail to start. Forced install, or issue with AMDGCF file?'
    $index = Find-AsciiString $bytes $needle
    Add "$Label AMDGCF_STRING_PRESENT=$($index -ge 0) offset=$(if ($index -ge 0) { '0x{0:X}' -f $index } else { 'n/a' })"
    if ($KnownGateOffset -ge 0 -and $KnownGateOffset -lt $bytes.Length) {
        Add "$Label GATE_BYTE_AT_0x$('{0:X}' -f $KnownGateOffset)=$('{0:X2}' -f $bytes[$KnownGateOffset]) $(Format-HexContext $bytes $KnownGateOffset)"
    }
}

function Analyze-Gcf([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add "$Label GCF_PRESENT=False"
        return
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $count = [BitConverter]::ToInt32($bytes, 0)
    Add "$Label GCF_PRESENT=True SHA256=$hash size=$($bytes.Length) entryCount=$count"
    $patterns = @(
        @{ Name = '407340'; Bytes = [byte[]](0x40, 0x73, 0x40) },
        @{ Name = '7340'; Bytes = [byte[]](0x73, 0x40) },
        @{ Name = '020F106B'; Bytes = [byte[]](0x02, 0x0F, 0x10, 0x6B) }
    )
    foreach ($pattern in $patterns) {
        $found = Find-AsciiString $bytes ([Text.Encoding]::ASCII.GetString($pattern.Bytes))
        Add "$Label PATTERN_$($pattern.Name)_PRESENT=$($found -ge 0) offset=$(if ($found -ge 0) { '0x{0:X}' -f $found } else { 'n/a' })"
    }
    if ($bytes.Length -ge 345) {
        Add "$Label OFFSET_342_BYTES=$('{0:X2} {1:X2} {2:X2}' -f $bytes[342], $bytes[343], $bytes[344])"
    }
}

try {
    Analyze-Kernel $Kernel2661 '26.6.1' 0x52A9F
    Analyze-Kernel $Kernel2521 '25.2.1'
    Analyze-Gcf $Gcf2661 '26.6.1'
    [IO.File]::WriteAllLines($ResultPath, $result, (New-Object Text.UTF8Encoding($false)))
    Add "RESULT_PATH=$ResultPath"
    exit 0
}
catch {
    Add "ERROR: $($_.Exception.Message)"
    [IO.File]::WriteAllLines($ResultPath, $result, (New-Object Text.UTF8Encoding($false)))
    exit 1
}
