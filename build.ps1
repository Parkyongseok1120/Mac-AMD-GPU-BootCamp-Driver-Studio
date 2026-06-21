param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [switch]$NoRestore
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root 'AMD.BootCamp.WinUI.csproj'
$dist = Join-Path $root 'dist'
$publish = Join-Path $dist 'AMD-BootCamp-Driver-Studio-2.5.0'
$zip = Join-Path $dist 'AMD-BootCamp-Driver-Studio-2.5.0-win-x64.zip'

if (Test-Path -LiteralPath $publish) { Remove-Item -LiteralPath $publish -Recurse -Force }
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
New-Item -ItemType Directory -Path $dist -Force | Out-Null

$publishArguments = @('publish', $project, '-c', $Configuration, '-r', 'win-x64', '--self-contained', 'true', '-o', $publish)
if ($NoRestore) { $publishArguments += '--no-restore' }
& dotnet @publishArguments
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }

Compress-Archive -LiteralPath $publish -DestinationPath $zip -CompressionLevel Optimal

Write-Host "Published: $publish"
Write-Host "Archive:   $zip"
