#Requires -RunAsAdministrator

param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$SoftwareSourceRoot = 'C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF',
    [string]$KernelSourceRoot = 'C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF',
    [string]$ResultPath = 'C:\AMD\whql-hybrid-26.6.1-25.2.1-result.txt',
    [switch]$ResumeAfterReboot,
    [switch]$PrepareOnly,
    [switch]$RunWhqlDiagnostics,
    [switch]$TestRollbackAfterInstall
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$profilePath = Join-Path $ProjectRoot 'Profiles\radeon-pro-5500m-original-kernel-hybrid.json'
$signScript = Join-Path $ProjectRoot 'Scripts\Sign-Package.ps1'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$prepareRoot = "C:\AMD\BootCampDriverStudio\Prepared\AMD-26.6.1-with-25.2.1-kernel-$stamp"
$link26Root = "C:\AMD\BootCampDriverStudio\Prepared\WHQL-Link-26.6.1-$stamp"
$link25Root = "C:\AMD\BootCampDriverStudio\Prepared\WHQL-Link-25.2.1-hybrid-$stamp"
$backupRoot = "C:\ProgramData\AMD BootCamp Driver Studio\Backups\before-whql-hybrid-$stamp"
$statePath = 'C:\AMD\whql-hybrid-26.6.1-25.2.1-pending.json'
$result = [System.Collections.Generic.List[string]]::new()
$driverChanged = $false
$backupInf = $null
$profile = $null
$hardwareId = $null

function Add-Result([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $result.Add($line)
    Write-Host $line
}

function Save-Result {
    New-Item -ItemType Directory -Path (Split-Path -Parent $ResultPath) -Force | Out-Null
    [IO.File]::WriteAllLines($ResultPath, $result, (New-Object Text.UTF8Encoding($false)))
}

function Get-ProfileHashMap($Profile) {
    $map = @{}
    foreach ($rule in $Profile.files) { $map[[string]$rule.path] = [string]$rule.sha256 }
    foreach ($source in $Profile.additionalSources) {
        foreach ($rule in $source.files) { $map["$([string]$source.id)/$([string]$rule.path)"] = [string]$rule.sha256 }
    }
    foreach ($copy in $Profile.sourceFileCopies) { $map["copy:$([string]$copy.destinationPath)"] = [string]$copy.sha256 }
    foreach ($assertion in $Profile.runtimeFileAssertions) { $map["runtime:$([string]$assertion.path)"] = [string]$assertion.sha256 }
    if ($Profile.files | Where-Object { $_.path -eq 'u0201163.inf' -and $_.patchedSha256 }) {
        $map['patched:u0201163.inf'] = [string]($Profile.files | Where-Object { $_.path -eq 'u0201163.inf' } | Select-Object -First 1).patchedSha256
    }
    return $map
}

function Assert-Hash([string]$Path, [string]$Expected, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Label missing: $Path" }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) { throw "$Label hash mismatch. Expected=$Expected Actual=$actual" }
    Add-Result "HASH_OK $Label=$actual"
}

function Get-Gpu([string]$Id) {
    Get-PnpDevice -PresentOnly -ErrorAction Stop |
        Where-Object { $_.InstanceId -like ($Id + '*') } |
        Select-Object -First 1
}

function Get-DriverProperty([string]$InstanceId, [string]$KeyName) {
    (Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop).Data
}

function Apply-RegistrySettings($Profile, $Gpu) {
    $driverKey = [string](Get-DriverProperty $Gpu.InstanceId 'DEVPKEY_Device_Driver')
    $classPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey"
    foreach ($setting in $Profile.registrySettings) {
        $path = if ([string]::IsNullOrWhiteSpace([string]$setting.subKey)) { $classPath } else { Join-Path $classPath ([string]$setting.subKey) }
        if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
        $kind = if ([string]$setting.kind -eq 'DWord') { 'DWord' } else { 'String' }
        $value = if ($kind -eq 'DWord') { [int]$setting.value } else { [string]$setting.value }
        New-ItemProperty -LiteralPath $path -Name ([string]$setting.name) -PropertyType $kind -Value $value -Force | Out-Null
    }
    Add-Result "REGISTRY_SETTINGS_APPLIED count=$($Profile.registrySettings.Count)"
}

function Apply-TextPatch($Patch, [string]$Root) {
    if ([string]$Patch.type -ne 'TextReplace') { throw "Non-text patch rejected: $($Patch.type)" }
    $file = Join-Path $Root ([string]$Patch.file -replace '/', '\')
    $text = [IO.File]::ReadAllText($file, [Text.Encoding]::ASCII)
    $search = [string]$Patch.search
    $replacement = [string]$Patch.replacement
    $count = 0
    for ($index = 0; ($index = $text.IndexOf($search, $index, [StringComparison]::Ordinal)) -ge 0; $index += $search.Length) { $count++ }
    if ($count -ne [int]$Patch.expectedOccurrences) {
        throw "Text patch count mismatch for $($Patch.file). Expected=$($Patch.expectedOccurrences), Actual=$count"
    }
    [IO.File]::WriteAllText($file, $text.Replace($search, $replacement), [Text.Encoding]::ASCII)
    Add-Result "TEXT_PATCH_OK $($Patch.file) occurrences=$count"
}

function New-WhqlLink([string]$SourceRoot, [string]$InfName, [string]$CatName, [string]$BinaryFolder, [string]$Destination) {
    New-Item -ItemType Directory -Path (Join-Path $Destination $BinaryFolder) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $SourceRoot $InfName) -Destination $Destination
    Copy-Item -LiteralPath (Join-Path $SourceRoot $CatName) -Destination $Destination
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $SourceRoot $BinaryFolder) -File) {
        New-Item -ItemType File -Path (Join-Path $Destination ($BinaryFolder + '\' + $file.Name)) -Force | Out-Null
    }
    $placeholders = Get-ChildItem -LiteralPath (Join-Path $Destination $BinaryFolder) -File
    if (($placeholders | Where-Object Length -ne 0).Count -ne 0) { throw "Non-zero WHQL placeholder in $Destination" }
    Add-Result "WHQL_LINK_CREATED=$Destination placeholders=$($placeholders.Count)"
}

function Invoke-WhqlDiagnostics([string]$OutputPath) {
    $dx = Start-Process -FilePath "$env:windir\System32\dxdiag.exe" `
        -ArgumentList "/dontskip /whql:on /t `"$OutputPath`"" -WindowStyle Hidden -PassThru
    if (-not $dx.WaitForExit(120000)) { $dx.Kill(); throw 'dxdiag timed out.' }
    Start-Sleep -Seconds 2
    if (-not (Test-Path -LiteralPath $OutputPath)) { throw "dxdiag output missing: $OutputPath" }
    $dxText = Get-Content -LiteralPath $OutputPath -Raw
    $matched = $dxText -match 'Card name:\s+AMD Radeon Pro 5500M[\s\S]{0,4000}WHQL Logo.d:\s+Yes'
    Add-Result "DXDIAG_WHQL_MARKER=$matched path=$OutputPath"
    return $matched
}

function Restore-Backup($Profile, [string]$Id) {
    if (-not $script:backupInf -or -not (Test-Path -LiteralPath $script:backupInf)) {
        Add-Result 'ROLLBACK_SKIPPED backup INF is unavailable.'
        return $false
    }
    Add-Result "ROLLBACK_BEGIN=$script:backupInf"
    $gpu = Get-Gpu $Id
    if ($gpu) {
        $currentInf = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverInfPath')
        if ($currentInf -match '^oem\d+\.inf$') {
            $deleteOutput = & pnputil.exe /delete-driver $currentInf /uninstall /force 2>&1 | Out-String
            $result.Add($deleteOutput.Trim())
            Add-Result "ROLLBACK_DELETE_EXIT=$LASTEXITCODE INF=$currentInf"
        }
    }
    $restoreOutput = & pnputil.exe /add-driver $script:backupInf /install 2>&1 | Out-String
    $restoreExit = $LASTEXITCODE
    $result.Add($restoreOutput.Trim())
    Add-Result "ROLLBACK_INSTALL_EXIT=$restoreExit"
    Start-Sleep -Seconds 8
    $gpu = Get-Gpu $Id
    if ($gpu) {
        Apply-RegistrySettings $Profile $gpu
        $restartOutput = & pnputil.exe /restart-device $gpu.InstanceId 2>&1 | Out-String
        $result.Add($restartOutput.Trim())
        Add-Result "ROLLBACK_RESTART_EXIT=$LASTEXITCODE"
        Start-Sleep -Seconds 20
        $gpu = Get-Gpu $Id
        $code = [uint32](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_ProblemCode')
        $version = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverVersion')
        Add-Result "ROLLBACK_FINAL_STATUS=$($gpu.Status) CODE=$code VERSION=$version"
        return ($code -eq 0 -and $version -eq '32.0.12033.5029')
    }
    return $false
}

function Save-PendingState {
    [pscustomobject]@{
        PreparedRoot = $prepareRoot
        Link26Root = $link26Root
        Link25Root = $link25Root
        BackupRoot = $backupRoot
        BackupInf = $backupInf
        ProjectRoot = $ProjectRoot
        SoftwareSourceRoot = $SoftwareSourceRoot
        KernelSourceRoot = $KernelSourceRoot
        CreatedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
}

function Load-Profile {
    param([string]$Path)
    $loaded = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$loaded.installationMode -ne 'original-kernel-hybrid') {
        throw "Profile installationMode must be original-kernel-hybrid. Actual=$($loaded.installationMode)"
    }
    if ([bool]$loaded.kernelDriverModified) { throw 'The source profile permits kernel patching.' }
    return $loaded
}

function Prepare-HybridPackage($Profile, $Hashes) {
    Assert-Hash (Join-Path $SoftwareSourceRoot 'u0201163.inf') $Hashes['u0201163.inf'] '26.6.1 INF'
    Assert-Hash (Join-Path $SoftwareSourceRoot 'u0201163.cat') $Hashes['u0201163.cat'] '26.6.1 CAT'
    Assert-Hash (Join-Path $SoftwareSourceRoot 'B026079/amdkmdag.sys') $Hashes['B026079/amdkmdag.sys'] '26.6.1 kernel'
    Assert-Hash (Join-Path $SoftwareSourceRoot 'B026079/amdgcf.dat') $Hashes['B026079/amdgcf.dat'] '26.6.1 amdgcf.dat'
    Assert-Hash (Join-Path $KernelSourceRoot 'u0412654.inf') $Hashes['kernel-anchor-25.2.1/u0412654.inf'] '25.2.1 INF'
    Assert-Hash (Join-Path $KernelSourceRoot 'u0412654.cat') $Hashes['kernel-anchor-25.2.1/u0412654.cat'] '25.2.1 CAT'
    Assert-Hash (Join-Path $KernelSourceRoot 'B412641/amdkmdag.sys') $Hashes['copy:B026079/amdkmdag.sys'] '25.2.1 kernel'

    foreach ($catalog in @((Join-Path $SoftwareSourceRoot 'u0201163.cat'), (Join-Path $KernelSourceRoot 'u0412654.cat'))) {
        $sig = Get-AuthenticodeSignature -LiteralPath $catalog
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notlike 'CN=Microsoft Windows Hardware Compatibility Publisher*') {
            throw "Original Microsoft WHQL catalog is invalid: $catalog"
        }
    }

    $kernelSource = Join-Path $KernelSourceRoot 'B412641\amdkmdag.sys'
    $kernelSig = Get-AuthenticodeSignature -LiteralPath $kernelSource
    if ($kernelSig.Status -ne 'Valid' -or
        ($kernelSig.SignerCertificate.Subject -notlike 'CN=Advanced Micro Devices*' -and
         $kernelSig.SignerCertificate.Subject -notlike 'CN=Microsoft Windows Hardware Compatibility Publisher*')) {
        throw 'The 25.2.1 anchor kernel embedded signature is invalid.'
    }
    Add-Result "ORIGINAL_SIGNATURES_OK catalogs=Microsoft_WHCP kernel=$($kernelSig.SignerCertificate.Subject)"

    Copy-Item -LiteralPath $SoftwareSourceRoot -Destination $prepareRoot -Recurse
    Copy-Item -LiteralPath $kernelSource -Destination (Join-Path $prepareRoot 'B026079\amdkmdag.sys') -Force
    Add-Result "HYBRID_PACKAGE_COPIED=$prepareRoot"
    Add-Result "ORIGINAL_KERNEL_SUBSTITUTED 25.2.1=$($Hashes['copy:B026079/amdkmdag.sys'])"

    foreach ($patch in $Profile.patches) { Apply-TextPatch $patch $prepareRoot }
    $hybridInf = Join-Path $prepareRoot 'u0201163.inf'
    Assert-Hash $hybridInf $Hashes['patched:u0201163.inf'] 'hybrid INF'

    $unchanged = 0
    foreach ($source in Get-ChildItem -LiteralPath $SoftwareSourceRoot -Recurse -File) {
        $relative = $source.FullName.Substring($SoftwareSourceRoot.TrimEnd('\').Length + 1)
        if ($relative -in @('u0201163.inf', 'B026079\amdkmdag.sys')) { continue }
        $copy = Join-Path $prepareRoot $relative
        if (-not (Test-Path -LiteralPath $copy)) { throw "Hybrid file missing: $relative" }
        $sourceHash = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
        $copyHash = (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash
        if ($sourceHash -ne $copyHash) { throw "26.6.1 binary changed: $relative" }
        $unchanged++
    }

    foreach ($assertion in $Profile.runtimeFileAssertions) {
        $path = Join-Path $prepareRoot ($assertion.path -replace '/', '\')
        Assert-Hash $path $Hashes["runtime:$([string]$assertion.path)"] "prepared runtime $($assertion.path)"
    }
    Add-Result "ALL_26.6.1_NON_KERNEL_FILES_UNCHANGED count=$unchanged"

    & $signScript -PackageRoot $prepareRoot -KernelDriverPath 'B026079/amdkmdag.sys' `
        -CatalogFile 'amdgpu.cat' -CertificateSubject ([string]$Profile.certificateSubject) -SkipKernelSigning
    Add-Result 'LOCAL_HYBRID_CATALOG_SIGNED'
    & $signScript -PackageRoot $prepareRoot -KernelDriverPath 'B026079/amdkmdag.sys' `
        -CatalogFile 'amdgpu.cat' -CertificateSubject ([string]$Profile.certificateSubject) -SkipKernelSigning -ValidateOnly
    Add-Result 'LOCAL_HYBRID_SIGNATURE_VALID'
    return $hybridInf
}

function Assert-HybridRuntime($Profile, $Hashes, [string]$ExpectedVersion) {
    $gpu = Get-Gpu $hardwareId
    if (-not $gpu) { throw 'Supported GPU not found during runtime verification.' }
    $problemCode = [uint32](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_ProblemCode')
    $driverVersion = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverVersion')
    $driverInf = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverInfPath')
    Add-Result "HYBRID_STATUS=$($gpu.Status) CODE=$problemCode VERSION=$driverVersion INF=$driverInf"
    if ($problemCode -ne 0 -or $driverVersion -ne $ExpectedVersion) {
        throw "Hybrid runtime check failed. Code=$problemCode Version=$driverVersion"
    }

    $service = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_Service')
    $imagePath = [string](Get-ItemPropertyValue "HKLM:\SYSTEM\CurrentControlSet\Services\$service" -Name ImagePath)
    $loadedKernel = $imagePath -replace '^\\SystemRoot', $env:windir
    Assert-Hash $loadedKernel $Hashes['runtime:B026079/amdkmdag.sys'] 'loaded hybrid kernel'
    $activeRepo = Split-Path -Parent (Split-Path -Parent $loadedKernel)
    $loadedUmd = Join-Path $activeRepo 'B026079\amdxx64.dll'
    Assert-Hash $loadedUmd $Hashes['runtime:B026079/amdxx64.dll'] 'loaded 26.6.1 amdxx64.dll'
    $loadedGcf = Join-Path $activeRepo 'B026079\amdgcf.dat'
    Assert-Hash $loadedGcf $Hashes['runtime:B026079/amdgcf.dat'] 'loaded 26.6.1 amdgcf.dat'
    Add-Result "HYBRID_COMPONENTS_OK kernel=25.2.1 user_mode=26.6.1 service=$service"
}

try {
    $profile = Load-Profile $profilePath
    $hardwareId = [string]$profile.supportedHardwareIds[0]
    $hashes = Get-ProfileHashMap $profile

    if ($ResumeAfterReboot) {
        if (-not (Test-Path -LiteralPath $statePath)) { throw "Pending hybrid state not found: $statePath" }
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $prepareRoot = [string]$state.PreparedRoot
        $link26Root = [string]$state.Link26Root
        $link25Root = [string]$state.Link25Root
        $backupRoot = [string]$state.BackupRoot
        $backupInf = [string]$state.BackupInf
        if ($state.ProjectRoot) { $ProjectRoot = [string]$state.ProjectRoot }
        if ($state.SoftwareSourceRoot) { $SoftwareSourceRoot = [string]$state.SoftwareSourceRoot }
        if ($state.KernelSourceRoot) { $KernelSourceRoot = [string]$state.KernelSourceRoot }
        $driverChanged = $true
        Add-Result "RESUME_AFTER_REBOOT prepared=$prepareRoot"

        $startOptions = [string](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions)
        if (($startOptions -split '\s+') -contains 'TESTSIGNING') { throw 'TESTSIGNING is active after reboot.' }
        Assert-HybridRuntime $profile $hashes '32.0.21043.12001'
        $gpu = Get-Gpu $hardwareId
        Apply-RegistrySettings $profile $gpu

        if ($RunWhqlDiagnostics) {
            New-WhqlLink $SoftwareSourceRoot 'u0201163.inf' 'u0201163.cat' 'B026079' $link26Root
            New-WhqlLink $KernelSourceRoot 'u0412654.inf' 'u0412654.cat' 'B412641' $link25Root
            foreach ($linkInf in @((Join-Path $link25Root 'u0412654.inf'), (Join-Path $link26Root 'u0201163.inf'))) {
                $linkOutput = & pnputil.exe /add-driver $linkInf /install 2>&1 | Out-String
                $result.Add($linkOutput.Trim())
                Add-Result "WHQL_LINK_INSTALL_EXIT=$LASTEXITCODE INF=$linkInf"
            }
            Invoke-WhqlDiagnostics "C:\AMD\dxdiag-whql-hybrid-26.6.1-25.2.1-$stamp.txt" | Out-Null
        }

        Add-Result "FINAL_TESTSIGNING_OFF SystemStartOptions=$startOptions"
        Remove-Item -LiteralPath $statePath -Force
        $driverChanged = $false
        Save-Result
        exit 0
    }

    $startOptions = [string](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions)
    Add-Result "SystemStartOptions=$startOptions"
    if (-not $PrepareOnly -and ($startOptions -split '\s+') -contains 'TESTSIGNING') { throw 'TESTSIGNING is active.' }

    $hybridInf = Prepare-HybridPackage $profile $hashes
    if ($PrepareOnly) {
        Add-Result "PREPARE_ONLY_ROOT=$prepareRoot"
        Save-Result
        exit 0
    }

    $gpu = Get-Gpu $hardwareId
    if (-not $gpu) { throw "Supported GPU not found: $hardwareId" }
    $initialCode = [uint32](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_ProblemCode')
    $initialVersion = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverVersion')
    Add-Result "INITIAL_STATUS=$($gpu.Status) CODE=$initialCode VERSION=$initialVersion"
    if ($initialCode -ne 0 -or $initialVersion -ne '32.0.12033.5029') {
        throw 'The verified 25.2.1 rollback anchor is not active.'
    }

    if ($RunWhqlDiagnostics) {
        New-WhqlLink $SoftwareSourceRoot 'u0201163.inf' 'u0201163.cat' 'B026079' $link26Root
        New-WhqlLink $KernelSourceRoot 'u0412654.inf' 'u0412654.cat' 'B412641' $link25Root
    }

    $oldInf = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverInfPath')
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $exportOutput = & pnputil.exe /export-driver $oldInf $backupRoot 2>&1 | Out-String
    $result.Add($exportOutput.Trim())
    Add-Result "EXPORT_EXIT=$LASTEXITCODE BACKUP=$backupRoot"
    if ($LASTEXITCODE -ne 0) { throw "Rollback anchor export failed: $LASTEXITCODE" }
    $backupInf = Get-ChildItem -LiteralPath $backupRoot -Recurse -Filter 'u0412654.inf' -File | Select-Object -First 1 -ExpandProperty FullName
    if (-not $backupInf) { throw 'Rollback anchor INF was not exported.' }
    Add-Result "ROLLBACK_INF=$backupInf"

    $deleteOutput = & pnputil.exe /delete-driver $oldInf /uninstall /force 2>&1 | Out-String
    $result.Add($deleteOutput.Trim())
    Add-Result "DELETE_ANCHOR_EXIT=$LASTEXITCODE"
    if ($LASTEXITCODE -notin @(0, 3010)) { throw "Anchor removal failed: $LASTEXITCODE" }
    $driverChanged = $true

    Start-Sleep -Seconds 4
    $installOutput = & pnputil.exe /add-driver $hybridInf /install 2>&1 | Out-String
    $installExit = $LASTEXITCODE
    $result.Add($installOutput.Trim())
    Add-Result "HYBRID_INSTALL_EXIT=$installExit"
    if ($installExit -notin @(0, 3010)) { throw "Hybrid install failed: $installExit" }

    if ($TestRollbackAfterInstall) {
        throw 'Intentional rollback test after hybrid installation.'
    }

    Start-Sleep -Seconds 8
    $gpu = Get-Gpu $hardwareId
    if (-not $gpu) { throw 'GPU disappeared after hybrid installation.' }
    Apply-RegistrySettings $profile $gpu
    if ($installExit -eq 3010) {
        Save-PendingState
        Add-Result "PENDING_REBOOT_STATE=$statePath"
        Add-Result 'HYBRID_INSTALL_PENDING_REBOOT; verification will resume after Windows starts.'
        Save-Result
        shutdown.exe /r /t 60 /c "AMD WHQL hybrid driver verification requires a reboot."
        exit 0
    }

    $restartOutput = & pnputil.exe /restart-device $gpu.InstanceId 2>&1 | Out-String
    $result.Add($restartOutput.Trim())
    Add-Result "HYBRID_RESTART_EXIT=$LASTEXITCODE"
    if ($LASTEXITCODE -notin @(0, 3010)) { throw "Hybrid device restart failed: $LASTEXITCODE" }

    Start-Sleep -Seconds 25
    Assert-HybridRuntime $profile $hashes '32.0.21043.12001'

    if ($RunWhqlDiagnostics) {
        foreach ($linkInf in @((Join-Path $link25Root 'u0412654.inf'), (Join-Path $link26Root 'u0201163.inf'))) {
            $linkOutput = & pnputil.exe /add-driver $linkInf /install 2>&1 | Out-String
            $result.Add($linkOutput.Trim())
            Add-Result "WHQL_LINK_INSTALL_EXIT=$LASTEXITCODE INF=$linkInf"
        }
        Invoke-WhqlDiagnostics "C:\AMD\dxdiag-whql-hybrid-26.6.1-25.2.1-$stamp.txt" | Out-Null
    }

    $finalStartOptions = [string](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions)
    if (($finalStartOptions -split '\s+') -contains 'TESTSIGNING') { throw 'TESTSIGNING unexpectedly became active.' }
    Add-Result "FINAL_TESTSIGNING_OFF SystemStartOptions=$finalStartOptions"
    Add-Result "PREPARED_ROOT=$prepareRoot"
    Add-Result "WHQL_LINK_26_ROOT=$link26Root"
    Add-Result "WHQL_LINK_25_ROOT=$link25Root"
    Add-Result "BACKUP_ROOT=$backupRoot"
    Save-Result
    exit 0
}
catch {
    Add-Result "ERROR: $($_.Exception.Message)"
    if ($driverChanged -and $profile -and $hardwareId) {
        try {
            $restored = Restore-Backup $profile $hardwareId
            Add-Result "ROLLBACK_SUCCESS=$restored"
        }
        catch {
            Add-Result "ROLLBACK_ERROR: $($_.Exception.Message)"
        }
    }
    Add-Result "PREPARED_ROOT=$prepareRoot"
    Add-Result "WHQL_LINK_26_ROOT=$link26Root"
    Add-Result "WHQL_LINK_25_ROOT=$link25Root"
    Add-Result "BACKUP_ROOT=$backupRoot"
    Save-Result
    exit 1
}
