param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$BlockWindowsUpdate,
    [Parameter(Mandatory = $true)][string]$SuppressAdrenalin,
    [Parameter(Mandatory = $true)][string]$RelaunchExecutable,
    [Parameter(Mandatory = $true)][string]$LogPath
)

$ErrorActionPreference = 'Stop'
$exitCode = 1
$utf8 = New-Object Text.UTF8Encoding($false)

function Write-WorkerLog([string]$Level, [string]$Message) {
    $folder = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    $line = '[{0}] [{1}] {2}{3}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message, [Environment]::NewLine
    [IO.File]::AppendAllText($LogPath, $line, $utf8)
}

try {
    Write-WorkerLog 'INFO' 'The UI was closed before the display driver swap to avoid a stale WinUI compositor.'
    Write-WorkerLog 'INFO' 'Detached driver installation started.'

    $bridge = Join-Path $PSScriptRoot 'System-Bridge.ps1'
    $powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $powerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridge `
        -Action Install `
        -ProfilePath $ProfilePath `
        -PackageRoot $PackageRoot `
        -BlockWindowsUpdate $BlockWindowsUpdate `
        -SuppressAdrenalin $SuppressAdrenalin 2>&1 |
        ForEach-Object { Write-WorkerLog 'INFO' ([string]$_) }

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "System-Bridge failed with exit code $exitCode."
    }
    Write-WorkerLog 'INFO' 'Detached driver installation completed successfully.'
}
catch {
    Write-WorkerLog 'ERROR' $_.Exception.Message
    Write-WorkerLog 'ERROR' ([string]$_)
    $exitCode = 1
}
finally {
    Write-WorkerLog 'INFO' 'Waiting for the desktop compositor to recover before reopening the app.'
    Start-Sleep -Seconds 10
    try {
        Start-Process -FilePath $RelaunchExecutable -WorkingDirectory (Split-Path -Parent $RelaunchExecutable)
        Write-WorkerLog 'INFO' 'AMD Boot Camp Driver Studio was relaunched.'
    }
    catch {
        Write-WorkerLog 'ERROR' "Application relaunch failed: $($_.Exception.Message)"
        $exitCode = 1
    }
}

exit $exitCode
