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
$resultPath = Join-Path $env:LOCALAPPDATA 'AMD BootCamp Driver Studio\install-result.json'
$startedAt = Get-Date
$backupFolder = ''
$resultMessage = ''
$resultError = ''

function Save-InstallResult {
    $folder = Split-Path -Parent $resultPath
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    [pscustomobject]@{
        ProfileId = (Split-Path -Path $ProfilePath -LeafBase)
        PackageRoot = $PackageRoot
        LogPath = $LogPath
        BackupFolder = $backupFolder
        Success = ($exitCode -eq 0)
        ExitCode = $exitCode
        Message = $resultMessage
        Error = $resultError
        StartedAt = $startedAt
        CompletedAt = Get-Date
    } | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

function Write-WorkerLog([string]$Level, [string]$Message) {
    $folder = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    $line = '[{0}] [{1}] {2}{3}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message, [Environment]::NewLine
    [IO.File]::AppendAllText($LogPath, $line, $utf8)
}

try {
    if (Test-Path -LiteralPath $resultPath) {
        Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    }
    Write-WorkerLog 'INFO' 'The UI was closed before the display driver swap to avoid a stale WinUI compositor.'
    Write-WorkerLog 'INFO' 'Detached driver installation started.'

    $bridge = Join-Path $PSScriptRoot 'System-Bridge.ps1'
    $powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $output = & $powerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridge `
        -Action Install `
        -ProfilePath $ProfilePath `
        -PackageRoot $PackageRoot `
        -BlockWindowsUpdate $BlockWindowsUpdate `
        -SuppressAdrenalin $SuppressAdrenalin 2>&1

    foreach ($entry in $output) {
        Write-WorkerLog 'INFO' ([string]$entry)
    }

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "System-Bridge failed with exit code $exitCode."
    }
    $backupLine = $output |
        ForEach-Object { [string]$_ } |
        Where-Object { $_ -like 'BACKUP=*' } |
        Select-Object -Last 1
    if ($backupLine) {
        $backupFolder = ($backupLine -replace '^BACKUP=', '')
        if ($backupFolder -eq 'NONE') { $backupFolder = '' }
    }
    $resultMessage = 'Detached driver installation completed successfully.'
    Write-WorkerLog 'INFO' 'Detached driver installation completed successfully.'
}
catch {
    $resultError = $_.Exception.Message
    $resultMessage = 'Detached driver installation failed.'
    Write-WorkerLog 'ERROR' $_.Exception.Message
    Write-WorkerLog 'ERROR' ([string]$_)
    $exitCode = 1
}
finally {
    Save-InstallResult
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
