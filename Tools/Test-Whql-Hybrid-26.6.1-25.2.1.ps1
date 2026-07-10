#Requires -RunAsAdministrator

& (Join-Path $PSScriptRoot 'Test-Whql-Hybrid.ps1') @PSBoundParameters -ProfilePath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'Profiles\radeon-pro-5500m-original-kernel-hybrid.json')
