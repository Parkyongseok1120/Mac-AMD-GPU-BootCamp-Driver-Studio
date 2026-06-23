#Requires -RunAsAdministrator

param(
    [string]$ProjectRoot = 'C:\Users\YongseokPark\Documents\Github\Mac-AMD-GPU-BootCamp-Driver-Studio',
    [string]$SourceRoot = 'C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF',
    [string]$ResultPath = 'C:\AMD\textonly-no-testmode-clean-install.txt'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$profilePath = Join-Path $ProjectRoot 'Profiles\radeon-pro-5500m-text-only.json'
$signScript = Join-Path $ProjectRoot 'Scripts\Sign-Package.ps1'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$prepareRoot = "C:\AMD\BootCampDriverStudio\Prepared\AMD-26.6.1-textonly-notest-$stamp"
$backupRoot = "C:\ProgramData\AMD BootCamp Driver Studio\Backups\textonly-before-clean-$stamp"
$originalGcfSha256 = 'D1AC965FDD33ADE6C7554CA9E3DEF97845E109B7A53B4EE0B8BFCBBC44C68D2A'
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

function Get-Gpu([string]$HardwareId) {
    Get-PnpDevice -Class Display -PresentOnly -ErrorAction Stop |
        Where-Object { $_.InstanceId -like ($HardwareId + '*') } |
        Select-Object -First 1
}

function Get-DriverProperty([string]$InstanceId, [string]$KeyName) {
    (Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop).Data
}

try {
    $profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([bool]$profile.kernelDriverModified) {
        throw 'The selected profile permits kernel modification. Refusing the clean INF-only install.'
    }

    $startOptions = [string](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' `
        -Name SystemStartOptions -ErrorAction Stop)
    Add-Result "SystemStartOptions=$startOptions"
    if (($startOptions -split '\s+') -contains 'TESTSIGNING') {
        throw 'TESTSIGNING is active. The no-test-mode validation cannot continue.'
    }

    foreach ($rule in $profile.files) {
        $source = Join-Path $SourceRoot ([string]$rule.path -replace '/', '\')
        if (-not (Test-Path -LiteralPath $source)) { throw "Source file missing: $source" }
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        if ($hash -ne [string]$rule.sha256) {
            throw "Original hash mismatch for $($rule.path). Expected=$($rule.sha256), Actual=$hash"
        }
        Add-Result "SOURCE_HASH_OK $($rule.path)=$hash"
    }
    $sourceGcf = Join-Path $SourceRoot 'B026079\amdgcf.dat'
    $sourceGcfHash = (Get-FileHash -LiteralPath $sourceGcf -Algorithm SHA256).Hash
    if ($sourceGcfHash -ne $originalGcfSha256) {
        throw "Original amdgcf.dat hash mismatch. Expected=$originalGcfSha256, Actual=$sourceGcfHash"
    }
    Add-Result "SOURCE_HASH_OK B026079/amdgcf.dat=$sourceGcfHash"

    $kernelSource = Join-Path $SourceRoot ([string]$profile.kernelDriverPath -replace '/', '\')
    $kernelSignature = Get-AuthenticodeSignature -LiteralPath $kernelSource
    if ($kernelSignature.Status -ne 'Valid' -or
        $kernelSignature.SignerCertificate.Subject -notlike 'CN=Microsoft Windows Hardware Compatibility Publisher*') {
        throw "Original kernel signature is not a valid Microsoft WHCP signature: $($kernelSignature.Status)"
    }
    Add-Result "KERNEL_SIGNATURE_OK $($kernelSignature.SignerCertificate.Subject)"

    Copy-Item -LiteralPath $SourceRoot -Destination $prepareRoot -Recurse
    Add-Result "PACKAGE_COPIED=$prepareRoot"

    foreach ($patch in $profile.patches) {
        if ([string]$patch.type -ne 'TextReplace') {
            throw "Non-text patch rejected: $($patch.type) $($patch.file)"
        }
        $file = Join-Path $prepareRoot ([string]$patch.file -replace '/', '\')
        $text = [IO.File]::ReadAllText($file, [Text.Encoding]::ASCII)
        $search = [string]$patch.search
        $replacement = [string]$patch.replacement
        $count = 0
        for ($index = 0; ($index = $text.IndexOf($search, $index, [StringComparison]::Ordinal)) -ge 0; $index += $search.Length) {
            $count++
        }
        if ($count -ne [int]$patch.expectedOccurrences) {
            throw "Text patch count mismatch for $($patch.file). Expected=$($patch.expectedOccurrences), Actual=$count"
        }
        [IO.File]::WriteAllText($file, $text.Replace($search, $replacement), [Text.Encoding]::ASCII)
        Add-Result "TEXT_PATCH_OK $($patch.file) occurrences=$count"
    }

    $preparedInf = Join-Path $prepareRoot ([string]$profile.infName)
    $infRule = $profile.files | Where-Object { [string]$_.path -eq [string]$profile.infName } | Select-Object -First 1
    $preparedInfHash = (Get-FileHash -LiteralPath $preparedInf -Algorithm SHA256).Hash
    if ($preparedInfHash -ne [string]$infRule.patchedSha256) {
        throw "Patched INF hash mismatch. Expected=$($infRule.patchedSha256), Actual=$preparedInfHash"
    }
    Add-Result "PATCHED_INF_HASH_OK=$preparedInfHash"

    $preparedKernel = Join-Path $prepareRoot ([string]$profile.kernelDriverPath -replace '/', '\')
    $preparedKernelHash = (Get-FileHash -LiteralPath $preparedKernel -Algorithm SHA256).Hash
    $kernelRule = $profile.files | Where-Object { [string]$_.path -eq [string]$profile.kernelDriverPath } | Select-Object -First 1
    if ($preparedKernelHash -ne [string]$kernelRule.sha256) {
        throw 'The kernel binary changed while preparing the INF-only package.'
    }
    $preparedGcfHash = (Get-FileHash -LiteralPath (Join-Path $prepareRoot 'B026079\amdgcf.dat') -Algorithm SHA256).Hash
    if ($preparedGcfHash -ne $originalGcfSha256) {
        throw 'amdgcf.dat changed while preparing the INF-only package.'
    }
    Add-Result "BINARY_UNCHANGED amdkmdag.sys=$preparedKernelHash"
    Add-Result "BINARY_UNCHANGED amdgcf.dat=$preparedGcfHash"

    & $signScript -PackageRoot $prepareRoot `
        -KernelDriverPath ([string]$profile.kernelDriverPath) `
        -CatalogFile ([string]$profile.catalogFile) `
        -CertificateSubject ([string]$profile.certificateSubject) `
        -SkipKernelSigning
    Add-Result 'CATALOG_SIGNING_OK'

    & $signScript -PackageRoot $prepareRoot `
        -KernelDriverPath ([string]$profile.kernelDriverPath) `
        -CatalogFile ([string]$profile.catalogFile) `
        -CertificateSubject ([string]$profile.certificateSubject) `
        -SkipKernelSigning -ValidateOnly
    Add-Result 'SIGNATURE_VALIDATION_OK'

    $hardwareId = [string]$profile.supportedHardwareIds[0]
    $gpu = Get-Gpu $hardwareId
    if (-not $gpu) { throw "Supported GPU not found: $hardwareId" }
    $oldInf = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverInfPath')
    Add-Result "CURRENT_INF=$oldInf"
    if ($oldInf -notmatch '^oem\d+\.inf$') { throw "Current driver is not an OEM package: $oldInf" }

    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $exportOutput = & pnputil.exe /export-driver $oldInf $backupRoot 2>&1 | Out-String
    $exportExit = $LASTEXITCODE
    $result.Add($exportOutput.Trim())
    Add-Result "EXPORT_EXIT=$exportExit BACKUP=$backupRoot"
    if ($exportExit -ne 0) { throw "Driver backup failed with exit code $exportExit" }

    $deleteOutput = & pnputil.exe /delete-driver $oldInf /uninstall /force 2>&1 | Out-String
    $deleteExit = $LASTEXITCODE
    $result.Add($deleteOutput.Trim())
    Add-Result "DELETE_EXIT=$deleteExit"
    if ($deleteExit -notin @(0, 3010)) { throw "Old driver removal failed with exit code $deleteExit" }

    Start-Sleep -Seconds 4
    $installOutput = & pnputil.exe /add-driver $preparedInf /install 2>&1 | Out-String
    $installExit = $LASTEXITCODE
    $result.Add($installOutput.Trim())
    Add-Result "INSTALL_EXIT=$installExit"
    if ($installExit -notin @(0, 3010)) {
        throw "Clean INF-only install failed with exit code $installExit"
    }

    Start-Sleep -Seconds 8
    $gpu = Get-Gpu $hardwareId
    if (-not $gpu) { throw 'GPU disappeared after the clean install.' }
    $driverKey = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_Driver')
    $classPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey"
    foreach ($setting in $profile.registrySettings) {
        $path = if ([string]::IsNullOrWhiteSpace([string]$setting.subKey)) {
            $classPath
        } else {
            Join-Path $classPath ([string]$setting.subKey)
        }
        if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
        $kind = if ([string]$setting.kind -eq 'DWord') { 'DWord' } else { 'String' }
        $value = if ($kind -eq 'DWord') { [int]$setting.value } else { [string]$setting.value }
        New-ItemProperty -LiteralPath $path -Name ([string]$setting.name) `
            -PropertyType $kind -Value $value -Force | Out-Null
        Add-Result "REGISTRY_SET $($setting.name)=$value"
    }

    $restartOutput = & pnputil.exe /restart-device $gpu.InstanceId 2>&1 | Out-String
    $restartExit = $LASTEXITCODE
    $result.Add($restartOutput.Trim())
    Add-Result "RESTART_EXIT=$restartExit"
    if ($restartExit -notin @(0, 3010)) { throw "Device restart failed with exit code $restartExit" }

    Start-Sleep -Seconds 15
    $gpu = Get-PnpDevice -InstanceId $gpu.InstanceId -ErrorAction Stop
    $problemCode = [uint32](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_ProblemCode')
    $driverVersion = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverVersion')
    $driverInf = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverInfPath')
    Add-Result "FINAL_STATUS=$($gpu.Status)"
    Add-Result "FINAL_PROBLEM_CODE=$problemCode"
    Add-Result "FINAL_DRIVER_VERSION=$driverVersion"
    Add-Result "FINAL_DRIVER_INF=$driverInf"
    Add-Result "PREPARED_ROOT=$prepareRoot"
    Add-Result "BACKUP_ROOT=$backupRoot"
    Save-Result
    exit $(if ($problemCode -eq 0) { 0 } else { 43 })
}
catch {
    Add-Result "ERROR: $($_.Exception.Message)"
    Save-Result
    exit 1
}
