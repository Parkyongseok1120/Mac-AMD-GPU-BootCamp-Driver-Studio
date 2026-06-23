#Requires -RunAsAdministrator

param(
    [string]$ProjectRoot = 'C:\Users\YongseokPark\Documents\Github\Mac-AMD-GPU-BootCamp-Driver-Studio',
    [string]$SourceRoot = 'C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF',
    [string]$ResultPath = 'C:\AMD\whql-anchor-25.2.1-result.txt'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$profilePath = Join-Path $ProjectRoot 'Profiles\radeon-pro-5500m-whql-anchor-25.2.1.json'
$signScript = Join-Path $ProjectRoot 'Scripts\Sign-Package.ps1'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$prepareRoot = "C:\AMD\BootCampDriverStudio\Prepared\AMD-25.2.1-whql-anchor-$stamp"
$linkRoot = "C:\AMD\BootCampDriverStudio\Prepared\WHQL-Link-25.2.1-$stamp"
$backupRoot = "C:\ProgramData\AMD BootCamp Driver Studio\Backups\before-whql-anchor-$stamp"
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
    Get-PnpDevice -PresentOnly -ErrorAction Stop |
        Where-Object { $_.InstanceId -like ($HardwareId + '*') } |
        Select-Object -First 1
}

function Get-DriverProperty([string]$InstanceId, [string]$KeyName) {
    (Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop).Data
}

function Apply-TextPatch($Patch, [string]$Root) {
    if ([string]$Patch.type -ne 'TextReplace') {
        throw "Only TextReplace is allowed by this no-binary-modification test: $($Patch.type)"
    }

    $file = Join-Path $Root ([string]$Patch.file -replace '/', '\')
    $text = [IO.File]::ReadAllText($file, [Text.Encoding]::ASCII)
    $search = [string]$Patch.search
    $replacement = [string]$Patch.replacement
    $count = 0
    for ($index = 0; ($index = $text.IndexOf($search, $index, [StringComparison]::Ordinal)) -ge 0; $index += $search.Length) {
        $count++
    }
    if ($count -ne [int]$Patch.expectedOccurrences) {
        throw "Text patch count mismatch for $($Patch.file). Expected=$($Patch.expectedOccurrences), Actual=$count"
    }
    [IO.File]::WriteAllText($file, $text.Replace($search, $replacement), [Text.Encoding]::ASCII)
    Add-Result "TEXT_PATCH_OK $($Patch.file) occurrences=$count"
}

function Assert-PackageFilesUnchanged([string]$OriginalRoot, [string]$CopiedRoot, [string]$MutableInf) {
    $files = Get-ChildItem -LiteralPath $OriginalRoot -Recurse -File
    $checked = 0
    foreach ($source in $files) {
        $relative = $source.FullName.Substring($OriginalRoot.TrimEnd('\').Length + 1)
        if ($relative.Equals($MutableInf, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $copy = Join-Path $CopiedRoot $relative
        if (-not (Test-Path -LiteralPath $copy)) { throw "Prepared file missing: $relative" }
        if ($source.Length -ne (Get-Item -LiteralPath $copy).Length) { throw "Prepared file size changed: $relative" }
        $sourceHash = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
        $copyHash = (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash
        if ($sourceHash -ne $copyHash) { throw "Prepared AMD file changed: $relative" }
        $checked++
    }
    Add-Result "ALL_NON_INF_FILES_UNCHANGED count=$checked"
}

try {
    $profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([bool]$profile.kernelDriverModified) { throw 'Profile permits kernel modification.' }

    $startOptions = [string](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions)
    Add-Result "SystemStartOptions=$startOptions"
    if (($startOptions -split '\s+') -contains 'TESTSIGNING') { throw 'TESTSIGNING is active.' }

    foreach ($rule in $profile.files) {
        $source = Join-Path $SourceRoot ([string]$rule.path -replace '/', '\')
        if (-not (Test-Path -LiteralPath $source)) { throw "Source file missing: $source" }
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        if ($hash -ne [string]$rule.sha256) {
            throw "Original hash mismatch for $($rule.path). Expected=$($rule.sha256), Actual=$hash"
        }
        Add-Result "SOURCE_HASH_OK $($rule.path)=$hash"
    }

    $kernelSource = Join-Path $SourceRoot ([string]$profile.kernelDriverPath -replace '/', '\')
    $kernelSignature = Get-AuthenticodeSignature -LiteralPath $kernelSource
    if ($kernelSignature.Status -ne 'Valid' -or
        ($kernelSignature.SignerCertificate.Subject -notlike 'CN=Advanced Micro Devices*' -and
         $kernelSignature.SignerCertificate.Subject -notlike 'CN=Microsoft Windows Hardware Compatibility Publisher*')) {
        throw "Original AMD kernel signature is invalid: $($kernelSignature.Status) $($kernelSignature.SignerCertificate.Subject)"
    }
    Add-Result "KERNEL_EMBEDDED_SIGNATURE_OK $($kernelSignature.SignerCertificate.Subject)"

    $originalCatalog = Join-Path $SourceRoot 'u0412654.cat'
    $catalogSignature = Get-AuthenticodeSignature -LiteralPath $originalCatalog
    if ($catalogSignature.Status -ne 'Valid' -or
        $catalogSignature.SignerCertificate.Subject -notlike 'CN=Microsoft Windows Hardware Compatibility Publisher*') {
        throw "Original catalog is not Microsoft WHCP signed: $($catalogSignature.Status)"
    }
    Add-Result "ORIGINAL_WHQL_CATALOG_OK $($catalogSignature.SignerCertificate.Subject)"

    Copy-Item -LiteralPath $SourceRoot -Destination $prepareRoot -Recurse
    Add-Result "PACKAGE_COPIED=$prepareRoot"
    foreach ($patch in $profile.patches) { Apply-TextPatch $patch $prepareRoot }

    $preparedInf = Join-Path $prepareRoot ([string]$profile.infName)
    $infRule = $profile.files | Where-Object { [string]$_.path -eq [string]$profile.infName } | Select-Object -First 1
    $preparedInfHash = (Get-FileHash -LiteralPath $preparedInf -Algorithm SHA256).Hash
    if ($preparedInfHash -ne [string]$infRule.patchedSha256) {
        throw "Patched INF hash mismatch. Expected=$($infRule.patchedSha256), Actual=$preparedInfHash"
    }
    Add-Result "PATCHED_INF_HASH_OK=$preparedInfHash"
    Assert-PackageFilesUnchanged $SourceRoot $prepareRoot ([string]$profile.infName)

    & $signScript -PackageRoot $prepareRoot `
        -KernelDriverPath ([string]$profile.kernelDriverPath) `
        -CatalogFile ([string]$profile.catalogFile) `
        -CertificateSubject ([string]$profile.certificateSubject) `
        -SkipKernelSigning
    Add-Result 'LOCAL_PACKAGE_CATALOG_SIGNED'

    & $signScript -PackageRoot $prepareRoot `
        -KernelDriverPath ([string]$profile.kernelDriverPath) `
        -CatalogFile ([string]$profile.catalogFile) `
        -CertificateSubject ([string]$profile.certificateSubject) `
        -SkipKernelSigning -ValidateOnly
    Add-Result 'LOCAL_PACKAGE_SIGNATURE_VALID'

    New-Item -ItemType Directory -Path (Join-Path $linkRoot 'B412641') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'u0412654.inf') -Destination $linkRoot
    Copy-Item -LiteralPath $originalCatalog -Destination $linkRoot
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $SourceRoot 'B412641') -File) {
        New-Item -ItemType File -Path (Join-Path $linkRoot ('B412641\' + $file.Name)) -Force | Out-Null
    }
    $zeroFiles = Get-ChildItem -LiteralPath (Join-Path $linkRoot 'B412641') -File
    if (($zeroFiles | Where-Object Length -ne 0).Count -ne 0) { throw 'WHQL link contains a non-zero placeholder.' }
    Add-Result "WHQL_LINK_CREATED=$linkRoot placeholders=$($zeroFiles.Count)"

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
    if ($exportExit -ne 0) { throw "Driver backup failed: $exportExit" }

    $deleteOutput = & pnputil.exe /delete-driver $oldInf /uninstall /force 2>&1 | Out-String
    $deleteExit = $LASTEXITCODE
    $result.Add($deleteOutput.Trim())
    Add-Result "DELETE_EXIT=$deleteExit"
    if ($deleteExit -notin @(0, 3010)) { throw "Old driver removal failed: $deleteExit" }

    Start-Sleep -Seconds 4
    $installOutput = & pnputil.exe /add-driver $preparedInf /install 2>&1 | Out-String
    $installExit = $LASTEXITCODE
    $result.Add($installOutput.Trim())
    Add-Result "ANCHOR_INSTALL_EXIT=$installExit"
    if ($installExit -notin @(0, 3010)) { throw "WHQL anchor install failed: $installExit" }

    Start-Sleep -Seconds 8
    $gpu = Get-Gpu $hardwareId
    if (-not $gpu) { throw 'GPU disappeared after anchor installation.' }
    $driverKey = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_Driver')
    $classPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey"
    foreach ($setting in $profile.registrySettings) {
        $path = if ([string]::IsNullOrWhiteSpace([string]$setting.subKey)) { $classPath } else { Join-Path $classPath ([string]$setting.subKey) }
        if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
        $kind = if ([string]$setting.kind -eq 'DWord') { 'DWord' } else { 'String' }
        $value = if ($kind -eq 'DWord') { [int]$setting.value } else { [string]$setting.value }
        New-ItemProperty -LiteralPath $path -Name ([string]$setting.name) -PropertyType $kind -Value $value -Force | Out-Null
    }
    Add-Result "REGISTRY_SETTINGS_APPLIED count=$($profile.registrySettings.Count)"

    $restartOutput = & pnputil.exe /restart-device $gpu.InstanceId 2>&1 | Out-String
    $restartExit = $LASTEXITCODE
    $result.Add($restartOutput.Trim())
    Add-Result "RESTART_EXIT=$restartExit"
    if ($restartExit -notin @(0, 3010)) { throw "Device restart failed: $restartExit" }

    Start-Sleep -Seconds 20
    $gpu = Get-Gpu $hardwareId
    $problemCode = [uint32](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_ProblemCode')
    $driverVersion = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverVersion')
    $driverInf = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverInfPath')
    Add-Result "ANCHOR_STATUS=$($gpu.Status) PROBLEM_CODE=$problemCode VERSION=$driverVersion INF=$driverInf"

    if ($problemCode -eq 0) {
        $linkInf = Join-Path $linkRoot 'u0412654.inf'
        $linkOutput = & pnputil.exe /add-driver $linkInf /install 2>&1 | Out-String
        $linkExit = $LASTEXITCODE
        $result.Add($linkOutput.Trim())
        Add-Result "WHQL_LINK_INSTALL_EXIT=$linkExit"
        if ($linkExit -notin @(0, 3010)) { throw "WHQL digital signature link install failed: $linkExit" }
    } else {
        Add-Result 'WHQL_LINK_SKIPPED because the anchor kernel did not start.'
    }

    $finalStartOptions = [string](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions)
    if (($finalStartOptions -split '\s+') -contains 'TESTSIGNING') { throw 'TESTSIGNING unexpectedly became active.' }
    Add-Result "FINAL_TESTSIGNING_OFF SystemStartOptions=$finalStartOptions"
    Add-Result "PREPARED_ROOT=$prepareRoot"
    Add-Result "WHQL_LINK_ROOT=$linkRoot"
    Add-Result "BACKUP_ROOT=$backupRoot"
    Save-Result
    exit $(if ($problemCode -eq 0) { 0 } else { 43 })
}
catch {
    Add-Result "ERROR: $($_.Exception.Message)"
    Add-Result "PREPARED_ROOT=$prepareRoot"
    Add-Result "WHQL_LINK_ROOT=$linkRoot"
    Add-Result "BACKUP_ROOT=$backupRoot"
    Save-Result
    exit 1
}
