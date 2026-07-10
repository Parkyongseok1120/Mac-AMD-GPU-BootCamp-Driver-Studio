#Requires -RunAsAdministrator

param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$SoftwareSourceRoot = 'C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF',
    [string]$KernelSourceRoot = 'C:\AMD\Official\AMD-25.2.1\Packages\Drivers\Display\WT6A_INF',
    [string]$ResultPath = 'C:\AMD\hybrid-clean-install-checklist.txt'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$lines = @(
    'Hybrid clean-install checklist',
    '',
    '1. Boot Camp Windows starts with Microsoft Basic Display Adapter or the 25.2.1 WHQL anchor only.',
    '2. TESTSIGNING is OFF.',
    '3. Official 26.6.1 and 25.2.1 packages pass Tools/Verify-OfficialPackages.ps1.',
    '4. Run Tools/Test-Anchor-Status.ps1 and confirm ANCHOR_READY=True, or install the anchor first.',
    '5. Run Tools/Test-Whql-Hybrid-26.6.1-25.2.1.ps1 and complete -ResumeAfterReboot if exit code 3010 occurs.',
    '6. Perform one manual cold boot and re-check kernel/UMD/GCF hashes.',
    '7. Run Tools/Capture-Driver-Diagnostics.ps1 and archive the output.',
    '8. Repeat once on a clean Boot Camp installation before promoting beyond Experimental.',
    '',
    "SoftwareSourceRoot=$SoftwareSourceRoot",
    "KernelSourceRoot=$KernelSourceRoot"
)
[IO.File]::WriteAllLines($ResultPath, $lines, (New-Object Text.UTF8Encoding($false)))
Write-Host "CHECKLIST_WRITTEN=$ResultPath"
