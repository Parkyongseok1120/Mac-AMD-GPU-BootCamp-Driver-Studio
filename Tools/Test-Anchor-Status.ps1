#Requires -RunAsAdministrator

param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ResultPath = 'C:\AMD\anchor-status-check.txt'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$result = [System.Collections.Generic.List[string]]::new()
$hardwareId = 'PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40'

function Add([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $result.Add($line)
    Write-Host $line
}

try {
    $gpu = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like ($hardwareId + '*') } | Select-Object -First 1
    if (-not $gpu) { throw "Target GPU not found: $hardwareId" }
    $code = [uint32](Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode').Data
    $version = [string](Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion').Data
    $inf = [string](Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath').Data
    $startOptions = [string](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions)
    Add "GPU_STATUS=$($gpu.Status) CODE=$code VERSION=$version INF=$inf"
    Add "SystemStartOptions=$startOptions"
    try {
        $secureBoot = Confirm-SecureBootUEFI
        Add "SecureBootEnabled=$secureBoot"
    }
    catch {
        Add "SecureBootEnabled=Unavailable"
    }
    if ($code -eq 0 -and $version -eq '32.0.12033.5029' -and (($startOptions -split '\s+') -notcontains 'TESTSIGNING')) {
        Add 'ANCHOR_READY=True'
        exit 0
    }
    Add 'ANCHOR_READY=False'
    [IO.File]::WriteAllLines($ResultPath, $result, (New-Object Text.UTF8Encoding($false)))
    exit 1
}
catch {
    Add "ERROR: $($_.Exception.Message)"
    [IO.File]::WriteAllLines($ResultPath, $result, (New-Object Text.UTF8Encoding($false)))
    exit 1
}
