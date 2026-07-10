#Requires -RunAsAdministrator

param(
    [string]$HardwareId = 'PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40',
    [string]$OutputRoot = 'C:\AMD\BootCampDriverStudio\Diagnostics',
    [string]$Label = 'manual'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$folder = Join-Path $OutputRoot "$stamp-$Label"
New-Item -ItemType Directory -Path $folder -Force | Out-Null

function Get-DeviceProperty([string]$InstanceId, [string]$KeyName) {
    try { return (Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop).Data }
    catch { return $null }
}

function Get-SecureBootState {
    try { return [bool](Confirm-SecureBootUEFI) }
    catch {
        $value = Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' `
            -Name UEFISecureBootEnabled -ErrorAction SilentlyContinue
        return [bool]$value
    }
}

$gpu = Get-PnpDevice -Class Display -PresentOnly -ErrorAction Stop |
    Where-Object { $_.InstanceId -like ($HardwareId + '*') } |
    Select-Object -First 1
if (-not $gpu) { throw "Target GPU was not found: $HardwareId" }

$instanceId = [string]$gpu.InstanceId
$service = [string](Get-DeviceProperty $instanceId 'DEVPKEY_Device_Service')
$driverKey = [string](Get-DeviceProperty $instanceId 'DEVPKEY_Device_Driver')
$serviceKey = if ($service) { "HKLM:\SYSTEM\CurrentControlSet\Services\$service" } else { $null }
$imagePath = if ($serviceKey -and (Test-Path -LiteralPath $serviceKey)) {
    [string](Get-ItemPropertyValue $serviceKey -Name ImagePath -ErrorAction Stop)
} else { '' }
$kernelPath = $imagePath -replace '^\\SystemRoot', $env:windir
$kernelHash = if ($kernelPath -and (Test-Path -LiteralPath $kernelPath)) {
    (Get-FileHash -LiteralPath $kernelPath -Algorithm SHA256).Hash
} else { '' }
$kernelSignature = if ($kernelPath -and (Test-Path -LiteralPath $kernelPath)) {
    Get-AuthenticodeSignature -LiteralPath $kernelPath
} else { $null }
$bcd = (& bcdedit.exe /enum '{current}' | Out-String)

$snapshot = [ordered]@{
    CapturedAt = (Get-Date).ToString('o')
    Label = $Label
    HardwareId = $HardwareId
    Gpu = [ordered]@{
        Name = [string]$gpu.FriendlyName
        Status = [string]$gpu.Status
        ProblemCode = [uint32](Get-DeviceProperty $instanceId 'DEVPKEY_Device_ProblemCode')
        DriverInf = [string](Get-DeviceProperty $instanceId 'DEVPKEY_Device_DriverInfPath')
        DriverVersion = [string](Get-DeviceProperty $instanceId 'DEVPKEY_Device_DriverVersion')
        Service = $service
        DriverKey = $driverKey
    }
    BootSecurity = [ordered]@{
        SecureBootEnabled = Get-SecureBootState
        TestSigningConfigured = $bcd -match '(?im)^testsigning\s+(Yes|On|True|1)'
        Bcd = $bcd.Trim()
    }
    ActiveKernel = [ordered]@{
        ImagePath = $kernelPath
        Sha256 = $kernelHash
        SignatureStatus = if ($kernelSignature) { [string]$kernelSignature.Status } else { '' }
        Signer = if ($kernelSignature) { [string]$kernelSignature.SignerCertificate.Subject } else { '' }
    }
}

$snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $folder 'snapshot.json') -Encoding UTF8
& pnputil.exe /enum-devices /instanceid $instanceId /drivers *> (Join-Path $folder 'pnputil-device.txt')
& pnputil.exe /enum-drivers /class Display *> (Join-Path $folder 'pnputil-display-drivers.txt')

$setupApi = Join-Path $env:windir 'INF\setupapi.dev.log'
if (Test-Path -LiteralPath $setupApi) {
    Select-String -LiteralPath $setupApi -Pattern ([regex]::Escape($HardwareId)) -Context 12,36 |
        ForEach-Object { $_.ToString(); $_.Context.PreContext; $_.Context.PostContext } |
        Set-Content -LiteralPath (Join-Path $folder 'setupapi-target.txt') -Encoding UTF8
}

Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddDays(-14) } -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProviderName -match 'amdkmdag|Display|Kernel-PnP' -or
        $_.Message -match 'amdkmdag|020F106B|Code 43|CM_PROB_FAILED_POST_START'
    } |
    Select-Object -First 160 TimeCreated, ProviderName, Id, LevelDisplayName, Message |
    Format-List | Out-File -LiteralPath (Join-Path $folder 'system-events.txt') -Encoding utf8

Write-Output "DIAGNOSTICS=$folder"
