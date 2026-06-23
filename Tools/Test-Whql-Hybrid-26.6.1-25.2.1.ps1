#Requires -RunAsAdministrator

param(
    [string]$ProjectRoot = 'C:\Users\YongseokPark\Documents\Github\Mac-AMD-GPU-BootCamp-Driver-Studio',
    [string]$SoftwareSourceRoot = 'C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF',
    [string]$KernelSourceRoot = 'C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF',
    [string]$ResultPath = 'C:\AMD\whql-hybrid-26.6.1-25.2.1-result.txt',
    [switch]$ResumeAfterReboot
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$profilePath = Join-Path $ProjectRoot 'Profiles\radeon-pro-5500m-text-only.json'
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

$expectedSoftwareInf = '5100D774A0FF67E1164D79061B7166D2CDC70C3E3A84A631D16A823707D94652'
$expectedSoftwareCat = '3DE64004A2B58579267D965AA9B99D15FEF08D00F6CCF2C0FAEF22C219E61BA1'
$expectedSoftwareKernel = '79AE113DF4EA446C01FA4F3300501D6E6854CB61A4A0F453BF5A7A4767EB1EB7'
$expectedSoftwareGcf = 'D1AC965FDD33ADE6C7554CA9E3DEF97845E109B7A53B4EE0B8BFCBBC44C68D2A'
$expectedAnchorInf = '4106300E195C080177D5F4D71A291C8978FF50B1511BD0696DE33B171A8ED55B'
$expectedAnchorCat = 'BB1FE286358DE820A09A60B89E666C33CB30A4079540C90043AC2DA78BBF6D69'
$expectedAnchorKernel = 'E04E80541F26F2AB76E67EEB5E006E0178C0240F831EE41BB0073E4F91B40799'
$expectedHybridInf = 'F56845625BE34DF5000E41C76BE857960B555B4D50C92AF065C11DA523681490'

function Add-Result([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $result.Add($line)
    Write-Host $line
}

function Save-Result {
    New-Item -ItemType Directory -Path (Split-Path -Parent $ResultPath) -Force | Out-Null
    [IO.File]::WriteAllLines($ResultPath, $result, (New-Object Text.UTF8Encoding($false)))
}

function Assert-Hash([string]$Path, [string]$Expected, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Label missing: $Path" }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) { throw "$Label hash mismatch. Expected=$Expected Actual=$actual" }
    Add-Result "HASH_OK $Label=$actual"
}

function Get-Gpu([string]$HardwareId) {
    Get-PnpDevice -PresentOnly -ErrorAction Stop |
        Where-Object { $_.InstanceId -like ($HardwareId + '*') } |
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

function Restore-Backup($Profile, [string]$HardwareId) {
    if (-not $script:backupInf -or -not (Test-Path -LiteralPath $script:backupInf)) {
        Add-Result 'ROLLBACK_SKIPPED backup INF is unavailable.'
        return
    }
    Add-Result "ROLLBACK_BEGIN=$script:backupInf"
    $gpu = Get-Gpu $HardwareId
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
    $gpu = Get-Gpu $HardwareId
    if ($gpu) {
        Apply-RegistrySettings $Profile $gpu
        $restartOutput = & pnputil.exe /restart-device $gpu.InstanceId 2>&1 | Out-String
        $result.Add($restartOutput.Trim())
        Add-Result "ROLLBACK_RESTART_EXIT=$LASTEXITCODE"
        Start-Sleep -Seconds 20
        $gpu = Get-Gpu $HardwareId
        $code = [uint32](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_ProblemCode')
        $version = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverVersion')
        Add-Result "ROLLBACK_FINAL_STATUS=$($gpu.Status) CODE=$code VERSION=$version"
    }
}

try {
    $profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([bool]$profile.kernelDriverModified) { throw 'The source profile permits kernel patching.' }
    $hardwareId = [string]$profile.supportedHardwareIds[0]

    if ($ResumeAfterReboot) {
        if (-not (Test-Path -LiteralPath $statePath)) { throw "Pending hybrid state not found: $statePath" }
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $prepareRoot = [string]$state.PreparedRoot
        $link26Root = [string]$state.Link26Root
        $link25Root = [string]$state.Link25Root
        $backupRoot = [string]$state.BackupRoot
        $backupInf = [string]$state.BackupInf
        $driverChanged = $true
        Add-Result "RESUME_AFTER_REBOOT prepared=$prepareRoot"

        $startOptions = [string](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions)
        if (($startOptions -split '\s+') -contains 'TESTSIGNING') { throw 'TESTSIGNING is active after reboot.' }
        $gpu = Get-Gpu $hardwareId
        if (-not $gpu) { throw 'GPU is missing after the hybrid reboot.' }
        $problemCode = [uint32](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_ProblemCode')
        $driverVersion = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverVersion')
        $driverInf = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverInfPath')
        Add-Result "POST_REBOOT_HYBRID_STATUS=$($gpu.Status) CODE=$problemCode VERSION=$driverVersion INF=$driverInf"
        if ($problemCode -ne 0 -or $driverVersion -ne '32.0.21043.12001') {
            throw "Hybrid did not start after reboot. Code=$problemCode Version=$driverVersion"
        }

        Apply-RegistrySettings $profile $gpu
        $service = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_Service')
        $imagePath = [string](Get-ItemPropertyValue "HKLM:\SYSTEM\CurrentControlSet\Services\$service" -Name ImagePath)
        $loadedKernel = $imagePath -replace '^\\SystemRoot', $env:windir
        Assert-Hash $loadedKernel $expectedAnchorKernel 'loaded hybrid kernel'
        $activeRepo = Split-Path -Parent (Split-Path -Parent $loadedKernel)
        $loadedUmd = Join-Path $activeRepo 'B026079\amdxx64.dll'
        $sourceUmd = Join-Path $SoftwareSourceRoot 'B026079\amdxx64.dll'
        Assert-Hash $loadedUmd ((Get-FileHash -LiteralPath $sourceUmd -Algorithm SHA256).Hash) 'loaded 26.6.1 amdxx64.dll'
        Add-Result "HYBRID_COMPONENTS_OK kernel=25.2.1 user_mode=26.6.1 service=$service"

        foreach ($linkInf in @((Join-Path $link25Root 'u0412654.inf'), (Join-Path $link26Root 'u0201163.inf'))) {
            $linkOutput = & pnputil.exe /add-driver $linkInf /install 2>&1 | Out-String
            $linkExit = $LASTEXITCODE
            $result.Add($linkOutput.Trim())
            Add-Result "WHQL_LINK_INSTALL_EXIT=$linkExit INF=$linkInf"
            if ($linkExit -notin @(0, 3010)) { throw "WHQL link install failed: $linkInf" }
        }

        $dxdiag = "C:\AMD\dxdiag-whql-hybrid-26.6.1-25.2.1-$stamp.txt"
        $dx = Start-Process -FilePath "$env:windir\System32\dxdiag.exe" `
            -ArgumentList "/dontskip /whql:on /t `"$dxdiag`"" -WindowStyle Hidden -PassThru
        if (-not $dx.WaitForExit(120000)) { $dx.Kill(); throw 'dxdiag timed out.' }
        Start-Sleep -Seconds 2
        $dxText = Get-Content -LiteralPath $dxdiag -Raw
        if ($dxText -notmatch 'Card name:\s+AMD Radeon Pro 5500M[\s\S]{0,4000}WHQL Logo.d:\s+Yes') {
            throw 'dxdiag did not report WHQL Logo as Yes for the hybrid driver.'
        }
        Add-Result "DXDIAG_WHQL_YES=$dxdiag"
        Add-Result "FINAL_TESTSIGNING_OFF SystemStartOptions=$startOptions"
        Remove-Item -LiteralPath $statePath -Force
        $driverChanged = $false
        Save-Result
        exit 0
    }

    $startOptions = [string](Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions)
    Add-Result "SystemStartOptions=$startOptions"
    if (($startOptions -split '\s+') -contains 'TESTSIGNING') { throw 'TESTSIGNING is active.' }

    $gpu = Get-Gpu $hardwareId
    if (-not $gpu) { throw "Supported GPU not found: $hardwareId" }
    $initialCode = [uint32](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_ProblemCode')
    $initialVersion = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverVersion')
    Add-Result "INITIAL_STATUS=$($gpu.Status) CODE=$initialCode VERSION=$initialVersion"
    if ($initialCode -ne 0 -or $initialVersion -ne '32.0.12033.5029') {
        throw 'The verified 25.2.1 rollback anchor is not active.'
    }

    Assert-Hash (Join-Path $SoftwareSourceRoot 'u0201163.inf') $expectedSoftwareInf '26.6.1 INF'
    Assert-Hash (Join-Path $SoftwareSourceRoot 'u0201163.cat') $expectedSoftwareCat '26.6.1 CAT'
    Assert-Hash (Join-Path $SoftwareSourceRoot 'B026079\amdkmdag.sys') $expectedSoftwareKernel '26.6.1 kernel'
    Assert-Hash (Join-Path $SoftwareSourceRoot 'B026079\amdgcf.dat') $expectedSoftwareGcf '26.6.1 amdgcf.dat'
    Assert-Hash (Join-Path $KernelSourceRoot 'u0412654.inf') $expectedAnchorInf '25.2.1 INF'
    Assert-Hash (Join-Path $KernelSourceRoot 'u0412654.cat') $expectedAnchorCat '25.2.1 CAT'
    Assert-Hash (Join-Path $KernelSourceRoot 'B412641\amdkmdag.sys') $expectedAnchorKernel '25.2.1 kernel'

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
    Add-Result "ORIGINAL_KERNEL_SUBSTITUTED 25.2.1=$expectedAnchorKernel"

    $hybridInf = Join-Path $prepareRoot 'u0201163.inf'
    $infText = [IO.File]::ReadAllText($hybridInf, [Text.Encoding]::ASCII)
    $catalogSearch = 'CatalogFile=u0201163.cat'
    if ([regex]::Matches($infText, [regex]::Escape($catalogSearch)).Count -ne 1) { throw 'CatalogFile patch count mismatch.' }
    [IO.File]::WriteAllText($hybridInf, $infText.Replace($catalogSearch, 'CatalogFile=amdgpu.cat'), [Text.Encoding]::ASCII)
    Add-Result 'TEXT_PATCH_OK CatalogFile occurrences=1'
    foreach ($patch in $profile.patches) { Apply-TextPatch $patch $prepareRoot }
    Assert-Hash $hybridInf $expectedHybridInf 'hybrid INF'

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
    Assert-Hash (Join-Path $prepareRoot 'B026079\amdkmdag.sys') $expectedAnchorKernel 'prepared anchor kernel'
    Add-Result "ALL_26.6.1_NON_KERNEL_FILES_UNCHANGED count=$unchanged"

    & $signScript -PackageRoot $prepareRoot -KernelDriverPath 'B026079/amdkmdag.sys' `
        -CatalogFile 'amdgpu.cat' -CertificateSubject ([string]$profile.certificateSubject) -SkipKernelSigning
    Add-Result 'LOCAL_HYBRID_CATALOG_SIGNED'
    & $signScript -PackageRoot $prepareRoot -KernelDriverPath 'B026079/amdkmdag.sys' `
        -CatalogFile 'amdgpu.cat' -CertificateSubject ([string]$profile.certificateSubject) -SkipKernelSigning -ValidateOnly
    Add-Result 'LOCAL_HYBRID_SIGNATURE_VALID'

    New-WhqlLink $SoftwareSourceRoot 'u0201163.inf' 'u0201163.cat' 'B026079' $link26Root
    New-WhqlLink $KernelSourceRoot 'u0412654.inf' 'u0412654.cat' 'B412641' $link25Root

    $oldInf = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverInfPath')
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $exportOutput = & pnputil.exe /export-driver $oldInf $backupRoot 2>&1 | Out-String
    $exportExit = $LASTEXITCODE
    $result.Add($exportOutput.Trim())
    Add-Result "EXPORT_EXIT=$exportExit BACKUP=$backupRoot"
    if ($exportExit -ne 0) { throw "Rollback anchor export failed: $exportExit" }
    $backupInf = Get-ChildItem -LiteralPath $backupRoot -Recurse -Filter 'u0412654.inf' -File | Select-Object -First 1 -ExpandProperty FullName
    if (-not $backupInf) { throw 'Rollback anchor INF was not exported.' }
    Add-Result "ROLLBACK_INF=$backupInf"

    $deleteOutput = & pnputil.exe /delete-driver $oldInf /uninstall /force 2>&1 | Out-String
    $deleteExit = $LASTEXITCODE
    $result.Add($deleteOutput.Trim())
    Add-Result "DELETE_ANCHOR_EXIT=$deleteExit"
    if ($deleteExit -notin @(0, 3010)) { throw "Anchor removal failed: $deleteExit" }
    $driverChanged = $true

    Start-Sleep -Seconds 4
    $installOutput = & pnputil.exe /add-driver $hybridInf /install 2>&1 | Out-String
    $installExit = $LASTEXITCODE
    $result.Add($installOutput.Trim())
    Add-Result "HYBRID_INSTALL_EXIT=$installExit"
    if ($installExit -notin @(0, 3010)) { throw "Hybrid install failed: $installExit" }

    Start-Sleep -Seconds 8
    $gpu = Get-Gpu $hardwareId
    if (-not $gpu) { throw 'GPU disappeared after hybrid installation.' }
    Apply-RegistrySettings $profile $gpu
    if ($installExit -eq 3010) {
        [pscustomobject]@{
            PreparedRoot = $prepareRoot
            Link26Root = $link26Root
            Link25Root = $link25Root
            BackupRoot = $backupRoot
            BackupInf = $backupInf
            CreatedAt = (Get-Date).ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
        Add-Result "PENDING_REBOOT_STATE=$statePath"
        Add-Result 'HYBRID_INSTALL_PENDING_REBOOT; verification will resume after Windows starts.'
        Save-Result
        shutdown.exe /r /t 60 /c "AMD WHQL hybrid driver verification requires a reboot."
        exit 0
    }
    $restartOutput = & pnputil.exe /restart-device $gpu.InstanceId 2>&1 | Out-String
    $restartExit = $LASTEXITCODE
    $result.Add($restartOutput.Trim())
    Add-Result "HYBRID_RESTART_EXIT=$restartExit"
    if ($restartExit -notin @(0, 3010)) { throw "Hybrid device restart failed: $restartExit" }

    Start-Sleep -Seconds 25
    $gpu = Get-Gpu $hardwareId
    $problemCode = [uint32](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_ProblemCode')
    $driverVersion = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverVersion')
    $driverInf = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_DriverInfPath')
    Add-Result "HYBRID_STATUS=$($gpu.Status) CODE=$problemCode VERSION=$driverVersion INF=$driverInf"
    if ($problemCode -ne 0) { throw "Hybrid kernel start failed with problem code $problemCode" }

    $service = [string](Get-DriverProperty $gpu.InstanceId 'DEVPKEY_Device_Service')
    $imagePath = [string](Get-ItemPropertyValue "HKLM:\SYSTEM\CurrentControlSet\Services\$service" -Name ImagePath)
    $loadedKernel = $imagePath -replace '^\\SystemRoot', $env:windir
    Assert-Hash $loadedKernel $expectedAnchorKernel 'loaded hybrid kernel'
    $activeRepo = Split-Path -Parent (Split-Path -Parent $loadedKernel)
    $loadedUmd = Join-Path $activeRepo 'B026079\amdxx64.dll'
    $sourceUmd = Join-Path $SoftwareSourceRoot 'B026079\amdxx64.dll'
    $sourceUmdHash = (Get-FileHash -LiteralPath $sourceUmd -Algorithm SHA256).Hash
    Assert-Hash $loadedUmd $sourceUmdHash 'loaded 26.6.1 amdxx64.dll'
    Add-Result "HYBRID_COMPONENTS_OK kernel=25.2.1 user_mode=26.6.1 service=$service"

    foreach ($linkInf in @((Join-Path $link25Root 'u0412654.inf'), (Join-Path $link26Root 'u0201163.inf'))) {
        $linkOutput = & pnputil.exe /add-driver $linkInf /install 2>&1 | Out-String
        $linkExit = $LASTEXITCODE
        $result.Add($linkOutput.Trim())
        Add-Result "WHQL_LINK_INSTALL_EXIT=$linkExit INF=$linkInf"
        if ($linkExit -notin @(0, 3010)) { throw "WHQL link install failed: $linkInf" }
    }

    $dxdiag = "C:\AMD\dxdiag-whql-hybrid-26.6.1-25.2.1-$stamp.txt"
    $dx = Start-Process -FilePath "$env:windir\System32\dxdiag.exe" `
        -ArgumentList "/dontskip /whql:on /t `"$dxdiag`"" -WindowStyle Hidden -PassThru
    if (-not $dx.WaitForExit(120000)) { $dx.Kill(); throw 'dxdiag timed out.' }
    Start-Sleep -Seconds 2
    $dxText = Get-Content -LiteralPath $dxdiag -Raw
    if ($dxText -notmatch 'Card name:\s+AMD Radeon Pro 5500M[\s\S]{0,4000}WHQL Logo.d:\s+Yes') {
        throw 'dxdiag did not report WHQL Logo as Yes for the hybrid driver.'
    }
    Add-Result "DXDIAG_WHQL_YES=$dxdiag"

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
    if ($driverChanged) {
        try { Restore-Backup $profile $hardwareId } catch { Add-Result "ROLLBACK_ERROR: $($_.Exception.Message)" }
    }
    Add-Result "PREPARED_ROOT=$prepareRoot"
    Add-Result "WHQL_LINK_26_ROOT=$link26Root"
    Add-Result "WHQL_LINK_25_ROOT=$link25Root"
    Add-Result "BACKUP_ROOT=$backupRoot"
    Save-Result
    exit 1
}
