#Requires -RunAsAdministrator

param(
    [string]$ProfilePath = 'C:\Users\YongseokPark\Documents\Github\Mac-AMD-GPU-BootCamp-Driver-Studio\Profiles\radeon-pro-5500m-text-only.json',
    [string]$ResultPath = 'C:\AMD\textonly-no-testmode-retry.txt'
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

try {
    $profile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([bool]$profile.kernelDriverModified) {
        throw 'The selected profile allows kernel modification. Refusing the INF-only retry.'
    }

    $startOptions = [string](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' `
        -Name SystemStartOptions -ErrorAction Stop)
    Add-Result "SystemStartOptions=$startOptions"
    if (($startOptions -split '\s+') -contains 'TESTSIGNING') {
        throw 'TESTSIGNING is active in the current boot session.'
    }

    $hardwareId = [string]$profile.supportedHardwareIds[0]
    $gpu = Get-PnpDevice -Class Display -PresentOnly -ErrorAction Stop |
        Where-Object { $_.InstanceId -like ($hardwareId + '*') } |
        Select-Object -First 1
    if (-not $gpu) { throw "Supported GPU not found: $hardwareId" }

    $driverKey = [string](Get-PnpDeviceProperty -InstanceId $gpu.InstanceId `
        -KeyName 'DEVPKEY_Device_Driver' -ErrorAction Stop).Data
    if ($driverKey -notmatch '^\{4d36e968-e325-11ce-bfc1-08002be10318\}\\\d{4}$') {
        throw "Unexpected display-class driver key: $driverKey"
    }
    $classPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey"
    Add-Result "GPU=$($gpu.FriendlyName)"
    Add-Result "INSTANCE=$($gpu.InstanceId)"
    Add-Result "DRIVER_KEY=$driverKey"

    foreach ($setting in $profile.registrySettings) {
        if ([string]$setting.root -ne 'DisplayClass') {
            throw "Unsupported registry root alias: $($setting.root)"
        }
        $path = if ([string]::IsNullOrWhiteSpace([string]$setting.subKey)) {
            $classPath
        } else {
            Join-Path $classPath ([string]$setting.subKey)
        }
        if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
        $name = [string]$setting.name
        if ([string]$setting.kind -eq 'DWord') {
            New-ItemProperty -LiteralPath $path -Name $name -PropertyType DWord `
                -Value ([int]$setting.value) -Force | Out-Null
        } elseif ([string]$setting.kind -eq 'String') {
            New-ItemProperty -LiteralPath $path -Name $name -PropertyType String `
                -Value ([string]$setting.value) -Force | Out-Null
        } else {
            throw "Unsupported registry kind: $($setting.kind)"
        }
        $actual = (Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop).PSObject.Properties[$name].Value
        if ([string]$actual -ne [string]$setting.value) {
            throw "Registry verification failed for $name. Expected=$($setting.value), Actual=$actual"
        }
        Add-Result "REGISTRY_OK $name=$actual"
    }

    Add-Result 'Restarting the display device after applying the complete INF-only registry profile.'
    $restartOutput = & pnputil.exe /restart-device $gpu.InstanceId 2>&1 | Out-String
    $restartExit = $LASTEXITCODE
    $result.Add($restartOutput.Trim())
    Add-Result "PNPUTIL_RESTART_EXIT=$restartExit"
    if ($restartExit -notin @(0, 3010)) {
        throw "Display device restart failed with exit code $restartExit"
    }

    Start-Sleep -Seconds 12
    $gpu = Get-PnpDevice -InstanceId $gpu.InstanceId -ErrorAction Stop
    $problemCode = [uint32](Get-PnpDeviceProperty -InstanceId $gpu.InstanceId `
        -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop).Data
    $driverVersion = [string](Get-PnpDeviceProperty -InstanceId $gpu.InstanceId `
        -KeyName 'DEVPKEY_Device_DriverVersion' -ErrorAction Stop).Data
    $driverInf = [string](Get-PnpDeviceProperty -InstanceId $gpu.InstanceId `
        -KeyName 'DEVPKEY_Device_DriverInfPath' -ErrorAction Stop).Data

    Add-Result "FINAL_STATUS=$($gpu.Status)"
    Add-Result "FINAL_PROBLEM_CODE=$problemCode"
    Add-Result "FINAL_DRIVER_VERSION=$driverVersion"
    Add-Result "FINAL_DRIVER_INF=$driverInf"
    Save-Result
    exit $(if ($problemCode -eq 0) { 0 } else { 43 })
}
catch {
    Add-Result "ERROR: $($_.Exception.Message)"
    Save-Result
    exit 1
}
