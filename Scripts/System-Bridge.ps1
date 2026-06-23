param(
    [Parameter(Mandatory = $true)][ValidateSet('Status','EnableTestSigning','DisableTestSigning','ConfigureDefaults','Install','Restore')][string]$Action,
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [string]$PackageRoot,
    [string]$BackupFolder,
    [string]$BlockWindowsUpdate = 'true',
    [string]$SuppressAdrenalin = 'true'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$profile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$hardwareId = [string]$profile.supportedHardwareIds[0]
$script:classNative = $null
$script:classPath = $null

function Get-Gpu {
    try {
        $gpu = Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.PNPDeviceID -like ($hardwareId + '*') } |
            Select-Object -First 1
        if ($gpu) { return $gpu }
    } catch {
        # Some hardened systems block broad CIM enumeration even though the
        # device-specific PnP cmdlets remain available.
    }

    try {
        $pnp = Get-PnpDevice -Class Display -PresentOnly -ErrorAction Stop |
            Where-Object { $_.InstanceId -like ($hardwareId + '*') } |
            Select-Object -First 1
        if ($pnp) {
            $problem = 0
            try {
                $problem = [uint32](Get-PnpDeviceProperty -InstanceId $pnp.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop).Data
            } catch {}
            return [pscustomobject]@{
                PNPDeviceID = [string]$pnp.InstanceId
                Name = [string]$pnp.FriendlyName
                ConfigManagerErrorCode = $problem
            }
        }
    } catch {
        # Fall through to the registry-backed lookup below.
    }

    $enumName = $hardwareId -replace '^PCI\\', ''
    $parent = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI' -ErrorAction Stop |
        Where-Object { $_.PSChildName -like ($enumName + '*') } |
        Select-Object -First 1
    if (-not $parent) { return $null }
    $instance = Get-ChildItem $parent.PSPath -ErrorAction Stop | Select-Object -First 1
    if (-not $instance) { return $null }
    $properties = Get-ItemProperty $instance.PSPath -ErrorAction Stop
    $name = [string]$properties.FriendlyName
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = ([string]$properties.DeviceDesc -split ';')[-1]
    }
    $problem = if ($null -ne $properties.Problem) { [uint32]$properties.Problem } else { 0 }
    [pscustomobject]@{
        PNPDeviceID = "PCI\$($parent.PSChildName)\$($instance.PSChildName)"
        Name = $name
        ConfigManagerErrorCode = $problem
    }
}

function Require-Gpu {
    $gpu = Get-Gpu
    if (-not $gpu) { throw "Supported GPU was not found: $hardwareId" }
    return $gpu
}

function Get-EnumProperties($Gpu) {
    $parts = [string]$Gpu.PNPDeviceID -split '\\', 3
    if ($parts.Count -ne 3 -or $parts[0] -ne 'PCI') { return $null }
    $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\$($parts[1])\$($parts[2])"
    Get-ItemProperty $path -ErrorAction Stop
}

function Get-DriverKey($Gpu) {
    try {
        return [string](Get-PnpDeviceProperty -InstanceId $Gpu.PNPDeviceID -KeyName 'DEVPKEY_Device_Driver' -ErrorAction Stop).Data
    } catch {
        return [string](Get-EnumProperties $Gpu).Driver
    }
}

function Get-CurrentInf($Gpu) {
    try { return (Get-PnpDeviceProperty -InstanceId $Gpu.PNPDeviceID -KeyName 'DEVPKEY_Device_DriverInfPath' -ErrorAction Stop).Data }
    catch {
        $driverKey = Get-DriverKey $Gpu
        if ([string]::IsNullOrWhiteSpace($driverKey)) { return $null }
        return (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey" -ErrorAction Stop).InfPath
    }
}

function Get-CurrentDriverVersion($Gpu) {
    try { return (Get-PnpDeviceProperty -InstanceId $Gpu.PNPDeviceID -KeyName 'DEVPKEY_Device_DriverVersion' -ErrorAction Stop).Data }
    catch {
        $driverKey = Get-DriverKey $Gpu
        if ([string]::IsNullOrWhiteSpace($driverKey)) { return '' }
        return (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey" -ErrorAction Stop).DriverVersion
    }
}

function Initialize-DisplayClassPaths($Gpu) {
    $driverKey = Get-DriverKey $Gpu
    if ([string]::IsNullOrWhiteSpace([string]$driverKey) -or [string]$driverKey -notmatch '^\{4d36e968-e325-11ce-bfc1-08002be10318\}\\\d{4}$') {
        throw "The active display-class registry instance could not be resolved: $driverKey"
    }
    $script:classNative = "HKLM\SYSTEM\CurrentControlSet\Control\Class\$driverKey"
    $script:classPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey"
}

function Try-InitializeDisplayClassPaths($Gpu) {
    try {
        Initialize-DisplayClassPaths $Gpu
        return $true
    } catch {
        $script:classNative = $null
        $script:classPath = $null
        Write-Output "DISPLAY_CLASS=NotReady:$($_.Exception.Message)"
        return $false
    }
}

function Test-SecureBoot {
    try { return [bool](Confirm-SecureBootUEFI) }
    catch {
        $registryValue = Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name UEFISecureBootEnabled -ErrorAction SilentlyContinue
        if ($null -ne $registryValue) { return [bool]$registryValue }
        if ($_.Exception.Message -match 'not supported|지원되지') { return $false }
        throw
    }
}

function Resolve-SafeChild([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -split '[\\/]' -contains '..') { throw "Unsafe relative path: $Relative" }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath((Join-Path $Root ($Relative -replace '/', '\')))
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escaped package root: $Relative" }
    return $full
}

function Enable-TestSigning {
    if (Test-SecureBoot) { throw 'Secure Boot is enabled. Select No Security in macOS Startup Security Utility first.' }
    & bcdedit.exe /set testsigning on | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "BCDEdit failed with exit code $LASTEXITCODE" }
}

function Disable-TestSigning {
    & bcdedit.exe /set testsigning off | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "BCDEdit failed with exit code $LASTEXITCODE" }
}

function Test-CurrentBootTestSigning {
    $options = [string](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' `
        -Name SystemStartOptions -ErrorAction SilentlyContinue)
    return ($options -split '\s+') -contains 'TESTSIGNING'
}

function Apply-ProfileRegistry {
    foreach ($setting in $profile.registrySettings) {
        switch ([string]$setting.root) {
            'DisplayClass' { $base = $classPath }
            default { throw "Unknown registry root alias: $($setting.root)" }
        }
        $path = if ([string]::IsNullOrWhiteSpace([string]$setting.subKey)) { $base } else { Join-Path $base ([string]$setting.subKey) }
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        if ([string]$setting.kind -eq 'DWord') {
            Set-ItemProperty -Path $path -Name ([string]$setting.name) -Type DWord -Value ([int]$setting.value)
        } else {
            Set-ItemProperty -Path $path -Name ([string]$setting.name) -Type String -Value ([string]$setting.value)
        }
    }
}

function Set-UpdateBlocks {
    if ([bool]::Parse($BlockWindowsUpdate)) {
        $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        $ds = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'
        if (-not (Test-Path $wu)) { New-Item -Path $wu -Force | Out-Null }
        Set-ItemProperty -Path $wu -Name ExcludeWUDriversInQualityUpdate -Type DWord -Value 1
        if (-not (Test-Path $ds)) { New-Item -Path $ds -Force | Out-Null }
        Set-ItemProperty -Path $ds -Name SearchOrderConfig -Type DWord -Value 0
    } else {
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name ExcludeWUDriversInQualityUpdate -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -Name SearchOrderConfig -ErrorAction SilentlyContinue
    }
    if ([bool]::Parse($SuppressAdrenalin)) {
        $cn = 'HKLM:\SOFTWARE\AMD\CN'
        $paths = @($cn)
        if (-not [string]::IsNullOrWhiteSpace([string]$classPath)) { $paths = @($classPath) + $paths }
        foreach ($path in $paths) {
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
            Set-ItemProperty -Path $path -Name Notify_DriverUpdate_hide -Type String -Value 'true'
            Set-ItemProperty -Path $path -Name driverupdate_ui_component_na -Type String -Value 'true'
            Set-ItemProperty -Path $path -Name driverupdate_runtime_component_na -Type String -Value 'true'
        }
    } else {
        $paths = @('HKLM:\SOFTWARE\AMD\CN')
        if (-not [string]::IsNullOrWhiteSpace([string]$classPath)) { $paths = @($classPath) + $paths }
        foreach ($path in $paths) {
            foreach ($name in @('Notify_DriverUpdate_hide', 'driverupdate_ui_component_na', 'driverupdate_runtime_component_na')) {
                Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
            }
        }
    }
}

if ($Action -eq 'Status') {
    $gpu = Get-Gpu
    $secureBoot = Test-SecureBoot
    $bcd = (& bcdedit.exe /enum all | Out-String)
    $testSigning = $false
    $prefix = 'testsigning'
    $reader = New-Object IO.StringReader($bcd)
    while (($line = $reader.ReadLine()) -ne $null) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $value = $trimmed.Substring($prefix.Length).Trim()
            $testSigning = $value -in @('Yes', 'On', 'True', '1')
            break
        }
    }
    $certSubject = [string]$profile.certificateSubject
    $certImported = $false
    if (-not [string]::IsNullOrWhiteSpace($certSubject)) {
        $certImported = [bool](
            (Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -eq $certSubject -and $_.NotAfter -gt (Get-Date) } |
                Select-Object -First 1) -and
            (Get-ChildItem Cert:\LocalMachine\TrustedPublisher -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -eq $certSubject -and $_.NotAfter -gt (Get-Date) } |
                Select-Object -First 1)
        )
    }
    $inf = if ($gpu) { Get-CurrentInf $gpu } else { '' }
    $version = if ($gpu) { Get-CurrentDriverVersion $gpu } else { '' }
    [ordered]@{
        HardwarePresent = [bool]$gpu
        GpuName = if ($gpu) { [string]$gpu.Name } else { '' }
        HardwareId = if ($gpu) { [string]$gpu.PNPDeviceID } else { '' }
        ProblemCode = if ($gpu) { [uint32]$gpu.ConfigManagerErrorCode } else { 0 }
        SecureBootEnabled = $secureBoot
        TestSigningConfigured = $testSigning
        TestSigningActive = [bool](Test-CurrentBootTestSigning)
        CertificateImported = $certImported
        DriverVersion = [string]$version
        DriverInf = [string]$inf
    } | ConvertTo-Json -Compress
    exit 0
}

if ($Action -eq 'EnableTestSigning') {
    Require-Gpu | Out-Null
    Enable-TestSigning
    Write-Output 'TESTSIGNING=EnabledForNextBoot'
    exit 0
}

if ($Action -eq 'DisableTestSigning') {
    Require-Gpu | Out-Null
    Disable-TestSigning
    Write-Output 'TESTSIGNING=DisabledForNextBoot'
    exit 0
}

if ($Action -eq 'ConfigureDefaults') {
    $gpu = Require-Gpu
    Try-InitializeDisplayClassPaths $gpu | Out-Null
    Set-UpdateBlocks
    Write-Output 'DEFAULTS=Configured'
    exit 0
}

if ($Action -eq 'Install') {
    if (-not (Test-Path -LiteralPath $PackageRoot)) { throw "Prepared package not found: $PackageRoot" }
    Write-Output "INSTALL_PROFILE=$($profile.id)"
    Write-Output "PACKAGE_ROOT=$PackageRoot"
    $gpu = Require-Gpu
    Write-Output "GPU=$($gpu.Name)"
    Try-InitializeDisplayClassPaths $gpu | Out-Null
    $kernelModified = if ($null -ne $profile.kernelDriverModified) { [bool]$profile.kernelDriverModified } else { $true }
    if ($kernelModified) {
        Enable-TestSigning
        Write-Output 'TESTSIGNING=EnabledForNextBoot'
        if (-not (Test-CurrentBootTestSigning)) {
            throw 'Test-signing is configured but is not active in the current Windows session. Restart Windows, then run installation.'
        }
    } else {
        $certSubject = [string]$profile.certificateSubject
        $certOk = (
            (Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -eq $certSubject -and $_.NotAfter -gt (Get-Date) } |
                Select-Object -First 1) -and
            (Get-ChildItem Cert:\LocalMachine\TrustedPublisher -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -eq $certSubject -and $_.NotAfter -gt (Get-Date) } |
                Select-Object -First 1)
        )
        if (-not $certOk) {
            throw "Local signing certificate '$certSubject' is not present in Root and TrustedPublisher stores. Run Prepare first to import it."
        }
        Write-Output 'TESTSIGNING=NotRequired'
    }
    $kernel = Resolve-SafeChild $PackageRoot ([string]$profile.kernelDriverPath)
    $catalog = Resolve-SafeChild $PackageRoot ([string]$profile.catalogFile)
    Write-Output 'SIGNATURE_CHECK=Started'
    $catSig = Get-AuthenticodeSignature -LiteralPath $catalog
    if ($catSig.Status -ne 'Valid' -or $catSig.SignerCertificate.Subject -ne [string]$profile.certificateSubject) {
        throw "Catalog signature validation failed: $catalog"
    }
    Write-Output "SIGNATURE_OK=$catalog"
    $kernelModified = if ($null -ne $profile.kernelDriverModified) { [bool]$profile.kernelDriverModified } else { $true }
    if ($kernelModified) {
        $kernelSig = Get-AuthenticodeSignature -LiteralPath $kernel
        if ($kernelSig.Status -ne 'Valid' -or $kernelSig.SignerCertificate.Subject -ne [string]$profile.certificateSubject) {
            throw "Kernel signature validation failed: $kernel"
        }
    } else {
        $kernelSig = Get-AuthenticodeSignature -LiteralPath $kernel
        if ($kernelSig.Status -ne 'Valid') {
            throw "Original kernel driver signature is invalid: $kernel"
        }
    }
    Write-Output "SIGNATURE_OK=$kernel"

    $currentInf = Get-CurrentInf $gpu
    $currentIsOem = -not [string]::IsNullOrWhiteSpace([string]$currentInf) -and [string]$currentInf -match '^oem\d+\.inf$'
    $backup = $null
    if ($currentIsOem) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backup = Join-Path $env:ProgramData "AMD BootCamp Driver Studio\Backups\$stamp"
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        Write-Output "BACKUP_FOLDER=$backup"
        Write-Output "DRIVER_EXPORT=$currentInf"
        & pnputil.exe /export-driver $currentInf $backup | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Driver backup failed with exit code $LASTEXITCODE" }
        if (-not [string]::IsNullOrWhiteSpace([string]$classNative)) {
            & reg.exe export $classNative (Join-Path $backup 'display-class.reg') /y | Out-Null
        }
        Copy-Item -LiteralPath $ProfilePath -Destination (Join-Path $backup 'profile.json') -Force
    } else {
        Write-Output "BACKUP=SkippedNoPreviousOemDriver:$currentInf"
    }

    if ($currentIsOem) {
        Write-Output "DRIVER_REMOVE=$currentInf"
        & pnputil.exe /delete-driver $currentInf /uninstall /force | Out-Null
        if ($LASTEXITCODE -notin @(0, 3010)) { throw "Driver removal failed with exit code $LASTEXITCODE" }
    }
    $inf = Resolve-SafeChild $PackageRoot ([string]$profile.infName)
    Write-Output "DRIVER_INSTALL=$inf"
    & pnputil.exe /add-driver $inf /install | Out-Null
    if ($LASTEXITCODE -notin @(0, 3010)) { throw "Driver installation failed with exit code $LASTEXITCODE" }

    $expectedVersion = [string]$profile.driverVersion
    $activeVersion = ''
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Seconds 1
        $gpu = Require-Gpu
        $activeVersion = [string](Get-CurrentDriverVersion $gpu)
        if ($activeVersion -eq $expectedVersion) { break }
    }
    if ($activeVersion -ne $expectedVersion) {
        throw "The newly installed driver did not become active. Expected $expectedVersion, active $activeVersion"
    }
    Initialize-DisplayClassPaths $gpu
    Write-Output "ACTIVE_DRIVER_VERSION=$activeVersion"
    Apply-ProfileRegistry
    Write-Output 'PROFILE_REGISTRY=Applied'
    Set-UpdateBlocks
    Write-Output 'UPDATE_POLICIES=Applied'
    Write-Output "BACKUP=$(if ($backup) { $backup } else { 'NONE' })"
    exit 0
}

if ($Action -eq 'Restore') {
    $gpu = Require-Gpu
    if (-not (Test-Path -LiteralPath $BackupFolder)) { throw "Backup folder not found: $BackupFolder" }
    $inf = Get-ChildItem -LiteralPath $BackupFolder -Filter '*.inf' -File -Recurse |
        Where-Object { Select-String -LiteralPath $_.FullName -Pattern 'DEV_7340' -Quiet } | Select-Object -First 1
    if (-not $inf) { throw 'No Radeon Pro 5500M INF was found in the backup.' }
    $currentInf = Get-CurrentInf $gpu
    if (-not [string]::IsNullOrWhiteSpace([string]$currentInf) -and [string]$currentInf -match '^oem\d+\.inf$') {
        & pnputil.exe /delete-driver $currentInf /uninstall /force | Out-Null
        if ($LASTEXITCODE -notin @(0, 3010)) { throw "Current driver removal failed with exit code $LASTEXITCODE" }
    } else {
        Write-Output "DRIVER_REMOVE=SkippedInboxDriver:$currentInf"
    }
    & pnputil.exe /add-driver $inf.FullName /install | Out-Null
    if ($LASTEXITCODE -notin @(0, 3010)) { throw "Backup restoration failed with exit code $LASTEXITCODE" }
    $registry = Join-Path $BackupFolder 'display-class.reg'
    if (Test-Path -LiteralPath $registry) { & reg.exe import $registry | Out-Null }
    Write-Output 'RESTORE=Completed'
}
