#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $false)]
    [string]$MsSignedCatalogPath = '',
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ProfilePath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'Profiles\radeon-pro-5500m-original-kernel-hybrid-26.6.4.json'),
    [string]$SoftwareSourceRoot = 'C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF',
    [string]$KernelSourceRoot = 'C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF',
    [string]$ResultPath = '',
    [switch]$ResumeAfterReboot,
    [switch]$RunWhqlDiagnostics,
    [switch]$TestRollbackAfterInstall
)

if (-not $ResumeAfterReboot -and -not $MsSignedCatalogPath) {
    throw 'MsSignedCatalogPath is required unless -ResumeAfterReboot is set.'
}

if (-not $ResultPath) {
    $ResultPath = 'C:\AMD\whql-hybrid-2664-ms-signed-result.txt'
}

& (Join-Path $PSScriptRoot 'Test-Whql-Hybrid.ps1') @PSBoundParameters
