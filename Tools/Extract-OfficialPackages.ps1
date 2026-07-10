#Requires -Version 5.1

param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$DestinationRoot = 'C:\AMD',
    [string]$LocalInstaller2521 = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

$profilePath = Join-Path $ProjectRoot 'Profiles\radeon-pro-5500m-whql-anchor-25.2.1.json'
$profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$info = [pscustomobject]@{
    Version = [string]$profile.marketingVersion
    FileName = [string]$profile.installerFileName
    Url = [string]$profile.installerUrl
    Sha256 = [string]$profile.installerSha256
    Size = [long]$profile.installerSize
    ExtractRoot = Join-Path $DestinationRoot 'Official\AMD-25.2.1'
    InfName = [string]$profile.infName
}

$folder = Join-Path $DestinationRoot 'Official'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$installerPath = Join-Path $folder $info.FileName
if ($LocalInstaller2521 -and (Test-Path -LiteralPath $LocalInstaller2521)) {
    Copy-Item -LiteralPath $LocalInstaller2521 -Destination $installerPath -Force
    Write-Host "INSTALLER_LOCAL_COPY=$LocalInstaller2521"
}
if (-not (Test-Path -LiteralPath $installerPath)) {
    Write-Host "DOWNLOAD_BEGIN=$($info.Url)"
    curl.exe -L --retry 5 --retry-delay 2 --output $installerPath $info.Url
}
if (-not (Test-Path -LiteralPath $installerPath)) { throw "Download failed: $($info.FileName)" }
$hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
$size = (Get-Item -LiteralPath $installerPath).Length
if ($hash -ne $info.Sha256) { throw "Installer SHA mismatch. Expected=$($info.Sha256) Actual=$hash" }
if ($info.Size -gt 0 -and $size -ne $info.Size) { throw "Installer size mismatch. Expected=$($info.Size) Actual=$size" }
Write-Host "DOWNLOAD_OK=$installerPath size=$size sha256=$hash"

$marker = Join-Path $info.ExtractRoot 'Packages\Drivers\Display\WT6A_INF'
if (-not (Test-Path -LiteralPath $marker)) {
    if (Test-Path -LiteralPath $info.ExtractRoot) { Remove-Item -LiteralPath $info.ExtractRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $info.ExtractRoot -Force | Out-Null
    $process = Start-Process -FilePath $installerPath -ArgumentList @('-INSTALL', '-PACKAGEPATH', $info.ExtractRoot) -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) { throw "Installer extract failed with exit code $($process.ExitCode)." }
}
if (-not (Test-Path -LiteralPath $marker)) { throw "Expected package root was not created: $marker" }
Write-Host "EXTRACT_OK=$marker"
Write-Host "INF=$(Join-Path $marker $info.InfName)"
exit 0
