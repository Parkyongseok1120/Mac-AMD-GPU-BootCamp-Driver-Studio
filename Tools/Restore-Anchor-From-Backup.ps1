#Requires -RunAsAdministrator

param(
    [string]$BackupFolder = 'C:\ProgramData\AMD BootCamp Driver Studio\Backups\20260710_212857',
    [string]$AnchorVersion = '32.0.12033.5029',
    [string]$HardwareId = 'PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40',
    [string]$ResultPath = 'C:\AMD\restore-anchor-result.txt'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$result = [System.Collections.Generic.List[string]]::new()

function Add-Result([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $result.Add($line)
    Write-Host $line
}

function Save-Result {
    New-Item -ItemType Directory -Path (Split-Path -Parent $ResultPath) -Force | Out-Null
    [IO.File]::WriteAllLines($ResultPath, $result, (New-Object Text.UTF8Encoding($false)))
}

function Get-Gpu {
    Get-PnpDevice -PresentOnly -ErrorAction Stop |
        Where-Object { $_.InstanceId -like ($HardwareId + '*') } |
        Select-Object -First 1
}

try {
    $startOptions = [string](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions)
    Add-Result "SystemStartOptions=$startOptions"
    if (($startOptions -split '\s+') -contains 'TESTSIGNING') {
        throw 'TESTSIGNING is active. Disable test-signing before restoring the WHQL anchor.'
    }

    if (-not (Test-Path -LiteralPath $BackupFolder)) {
        throw "Backup folder not found: $BackupFolder"
    }

    $restoreInf = Get-ChildItem -LiteralPath $BackupFolder -Filter 'u0412654.inf' -File -Recurse |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $restoreInf) {
        $restoreInf = Get-ChildItem -LiteralPath $BackupFolder -Filter '*.inf' -File -Recurse |
            Where-Object { Select-String -LiteralPath $_.FullName -Pattern 'DEV_7340' -Quiet } |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $restoreInf) { throw "No Radeon Pro 5500M anchor INF found under $BackupFolder" }
    Add-Result "RESTORE_INF=$restoreInf"

    $gpu = Get-Gpu
    if (-not $gpu) { throw "Supported GPU not found: $HardwareId" }
    $currentInf = [string]((Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath').Data)
    $currentVersion = [string]((Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion').Data)
    $problemCode = [uint32]((Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode').Data)
    Add-Result "BEFORE_STATUS=$($gpu.Status) CODE=$problemCode VERSION=$currentVersion INF=$currentInf"

    if ($currentVersion -eq $AnchorVersion -and $problemCode -eq 0) {
        Add-Result 'ANCHOR_ALREADY_ACTIVE=No restore required'
        Save-Result
        exit 0
    }

    if ($currentInf -match '^oem\d+\.inf$') {
        $deleteOutput = & pnputil.exe /delete-driver $currentInf /uninstall /force 2>&1 | Out-String
        $result.Add($deleteOutput.Trim())
        Add-Result "DELETE_EXIT=$LASTEXITCODE INF=$currentInf"
        if ($LASTEXITCODE -notin @(0, 3010)) { throw "Current driver removal failed: $LASTEXITCODE" }
        Start-Sleep -Seconds 4
    }

    $installOutput = & pnputil.exe /add-driver $restoreInf /install 2>&1 | Out-String
    $installExit = $LASTEXITCODE
    $result.Add($installOutput.Trim())
    Add-Result "RESTORE_INSTALL_EXIT=$installExit"
    if ($installExit -notin @(0, 3010)) { throw "Anchor restore failed: $installExit" }

    if ($installExit -eq 3010) {
        Add-Result 'RESTORE_PENDING_REBOOT=Reboot required to complete anchor restore'
        Save-Result
        exit 3010
    }

    Start-Sleep -Seconds 8
    $gpu = Get-Gpu
    $problemCode = [uint32]((Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode').Data)
    $currentVersion = [string]((Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion').Data)
    $currentInf = [string]((Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath').Data)
    Add-Result "AFTER_STATUS=$($gpu.Status) CODE=$problemCode VERSION=$currentVersion INF=$currentInf"

    if ($problemCode -ne 0 -or $currentVersion -ne $AnchorVersion) {
        throw "Anchor restore verification failed. CODE=$problemCode VERSION=$currentVersion"
    }

    Add-Result 'ANCHOR_RESTORE=PASS'
    Save-Result
    exit 0
}
catch {
    Add-Result "ERROR: $($_.Exception.Message)"
    Save-Result
    exit 1
}
