#Requires -RunAsAdministrator

param(
    [string]$ResultPath = 'C:\AMD\disable-testsigning-result.txt',
    [int]$RestartDelaySeconds = 60
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$bootEntry = '{current}'
$lines = [System.Collections.Generic.List[string]]::new()

function Add-Result([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $lines.Add($line)
    Write-Host $line
}

try {
    Add-Result 'Requesting TESTSIGNING=OFF for the current Windows boot loader.'

    $before = & bcdedit.exe /enum $bootEntry 2>&1 | Out-String
    $beforeExit = $LASTEXITCODE
    Add-Result "BCDEdit read-before exit=$beforeExit"
    if ($beforeExit -ne 0) { throw "BCDEdit could not read $bootEntry before the change.`n$before" }
    $lines.Add("--- BEFORE ---`r`n$before")

    $setOutput = & bcdedit.exe /set $bootEntry testsigning off 2>&1 | Out-String
    $setExit = $LASTEXITCODE
    Add-Result "BCDEdit set exit=$setExit output=$($setOutput.Trim())"
    if ($setExit -ne 0) { throw "BCDEdit failed to disable TESTSIGNING.`n$setOutput" }

    $after = & bcdedit.exe /enum $bootEntry 2>&1 | Out-String
    $afterExit = $LASTEXITCODE
    Add-Result "BCDEdit read-after exit=$afterExit"
    if ($afterExit -ne 0) { throw "BCDEdit could not verify $bootEntry after the change.`n$after" }
    $lines.Add("--- AFTER ---`r`n$after")

    $enabledLine = $after -split "`r?`n" | Where-Object {
        $_ -match '^\s*testsigning\s+(Yes|On|True|1)\s*$'
    }
    if ($enabledLine) { throw "TESTSIGNING still appears enabled after BCDEdit: $enabledLine" }

    Add-Result 'BCD verification passed: TESTSIGNING is not enabled for the next boot.'
    Add-Result "Restart scheduled in $RestartDelaySeconds seconds. Run 'shutdown /a' to cancel."
    New-Item -ItemType Directory -Path (Split-Path -Parent $ResultPath) -Force | Out-Null
    [IO.File]::WriteAllLines($ResultPath, $lines, (New-Object Text.UTF8Encoding($false)))

    & shutdown.exe /r /t $RestartDelaySeconds /c 'Restart to apply TESTSIGNING=OFF for AMD Boot Camp INF-only validation'
    if ($LASTEXITCODE -ne 0) { throw "Restart scheduling failed with exit code $LASTEXITCODE" }
    exit 0
}
catch {
    Add-Result "ERROR: $($_.Exception.Message)"
    New-Item -ItemType Directory -Path (Split-Path -Parent $ResultPath) -Force | Out-Null
    [IO.File]::WriteAllLines($ResultPath, $lines, (New-Object Text.UTF8Encoding($false)))
    exit 1
}
