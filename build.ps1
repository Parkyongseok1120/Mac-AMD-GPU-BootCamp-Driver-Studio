param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [switch]$NoRestore
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root 'AMD.BootCamp.WinUI.csproj'
$projectXml = [xml](Get-Content -LiteralPath $project -Raw)
$version = $projectXml.Project.PropertyGroup.Version | Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($version)) { throw "Project version not found in $project" }

$dist = Join-Path $root 'dist'
$publish = Join-Path $dist "AMD-BootCamp-Driver-Studio-$version"
$zip = Join-Path $dist "AMD-BootCamp-Driver-Studio-$version-win-x64.zip"

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
