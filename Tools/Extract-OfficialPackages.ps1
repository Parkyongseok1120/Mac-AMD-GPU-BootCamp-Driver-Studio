#Requires -Version 5.1

param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [ValidateSet('26.6.4', '26.6.1', '25.2.1', 'Both', 'HybridStack')]
    [string]$Package = 'HybridStack',
    [string]$DestinationRoot = 'C:\AMD',
    [string]$LocalInstaller2664 = '',
    [string]$LocalInstaller2661 = '',
    [string]$LocalInstaller2521 = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

$profiles = @{
    '26.6.4' = Join-Path $ProjectRoot 'Profiles\radeon-pro-5500m-original-kernel-hybrid-26.6.4.json'
    '26.6.1' = Join-Path $ProjectRoot 'Profiles\radeon-pro-5500m-original-kernel-hybrid.json'
    '25.2.1' = Join-Path $ProjectRoot 'Profiles\radeon-pro-5500m-whql-anchor-25.2.1.json'
}

function Get-ProfileInstallerInfo([string]$ProfilePath) {
    $profile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    return [pscustomobject]@{
        Version = [string]$profile.marketingVersion
        FileName = [string]$profile.installerFileName
        Url = [string]$profile.installerUrl
        Sha256 = [string]$profile.installerSha256
        Size = [long]$profile.installerSize
        ExtractRoot = if ([string]$profile.marketingVersion -match '^26\.6\.') {
            Join-Path $DestinationRoot 'AMD-Software-Installer'
        } else {
            Join-Path $DestinationRoot 'Official\AMD-25.2.1'
        }
        InfName = [string]$profile.infName
    }
}

function Download-VerifiedInstaller($Info, [string]$LocalInstallerPath) {
    $folder = Join-Path $DestinationRoot 'Official'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $path = Join-Path $folder $Info.FileName
    if ($LocalInstallerPath -and (Test-Path -LiteralPath $LocalInstallerPath)) {
        Copy-Item -LiteralPath $LocalInstallerPath -Destination $path -Force
        Write-Host "INSTALLER_LOCAL_COPY=$LocalInstallerPath"
    }
    if (Test-Path -LiteralPath $path) {
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $size = (Get-Item -LiteralPath $path).Length
        if ($hash -eq $Info.Sha256 -and ($Info.Size -le 0 -or $size -eq $Info.Size)) {
            Write-Host "INSTALLER_REUSE=$path"
            return $path
        }
        Remove-Item -LiteralPath $path -Force
    }

    Write-Host "DOWNLOAD_BEGIN=$($Info.Url)"
    curl.exe -L --retry 5 --retry-delay 2 --output $path $Info.Url
    if (-not (Test-Path -LiteralPath $path)) { throw "Download failed: $($Info.FileName)" }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $size = (Get-Item -LiteralPath $path).Length
    if ($hash -ne $Info.Sha256) { throw "Installer SHA mismatch for $($Info.Version). Expected=$($Info.Sha256) Actual=$hash" }
    if ($Info.Size -gt 0 -and $size -ne $Info.Size) { throw "Installer size mismatch for $($Info.Version). Expected=$($Info.Size) Actual=$size" }
    Write-Host "DOWNLOAD_OK=$path size=$size sha256=$hash"
    return $path
}

function Extract-Installer([string]$InstallerPath, [string]$ExtractRoot) {
    $marker = switch -Wildcard ($InstallerPath) {
        '*26.6.*' { Join-Path $ExtractRoot 'Packages\Drivers\Display2\WT6A_INF' }
        default { Join-Path $ExtractRoot 'Packages\Drivers\Display\WT6A_INF' }
    }
    if (Test-Path -LiteralPath $marker) {
        Write-Host "EXTRACT_REUSE=$marker"
        return $marker
    }
    if (Test-Path -LiteralPath $ExtractRoot) { Remove-Item -LiteralPath $ExtractRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $ExtractRoot -Force | Out-Null
    $process = Start-Process -FilePath $InstallerPath -ArgumentList @('-INSTALL', '-PACKAGEPATH', $ExtractRoot) -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) { throw "Installer extract failed with exit code $($process.ExitCode). Try GUI extract if CLI fails." }
    if (-not (Test-Path -LiteralPath $marker)) { throw "Expected package root was not created: $marker" }
    Write-Host "EXTRACT_OK=$marker"
    return $marker
}

$targets = switch ($Package) {
    'Both' { @('26.6.4', '25.2.1') }
    'HybridStack' { @('26.6.4', '25.2.1') }
    default { @($Package) }
}
$results = @()
foreach ($version in $targets) {
    $info = Get-ProfileInstallerInfo $profiles[$version]
    $local = switch ($version) {
        '26.6.4' { $LocalInstaller2664 }
        '26.6.1' { $LocalInstaller2661 }
        default { $LocalInstaller2521 }
    }
    $installer = Download-VerifiedInstaller $info $local
    $packageRoot = Extract-Installer $installer $info.ExtractRoot
    $results += [pscustomobject]@{
        Version = $version
        Installer = $installer
        PackageRoot = $packageRoot
        Inf = Join-Path $packageRoot $info.InfName
    }
}

$results | Format-Table -AutoSize
exit 0
