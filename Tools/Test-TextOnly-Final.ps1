#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

$LogPath     = 'C:\AMD\textonly-final-test.txt'
$ScriptDir   = 'C:\Users\YongseokPark\Documents\Github\Mac-AMD-GPU-BootCamp-Driver-Studio\Scripts'
$ProfilePath = 'C:\Users\YongseokPark\Documents\Github\Mac-AMD-GPU-BootCamp-Driver-Studio\Profiles\radeon-pro-5500m-text-only.json'
$SrcRoot     = 'C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF'
$PrepareRoot = 'C:\AMD\BootCampDriverStudio\Prepared\AMD-26.6.1-textonly-final'

Start-Transcript -Path $LogPath -Force | Out-Null
$prof = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host '=== STEP 1: Clean prepared folder ==='
if (Test-Path $PrepareRoot) { Remove-Item -Recurse -Force $PrepareRoot }
Copy-Item -Recurse $SrcRoot $PrepareRoot
Write-Host '  Done'

Write-Host '=== STEP 2: Verify original hashes ==='
foreach ($f in $prof.files) {
	$full = Join-Path $PrepareRoot ($f.path -replace '/', '\')
	$hash = (Get-FileHash $full -Algorithm SHA256).Hash
	if ($hash -ne $f.sha256) { throw "Hash mismatch: $($f.path)" }
	Write-Host "  PASS $($f.path)"
}

Write-Host '=== STEP 3: Apply patches (TextReplace only, zero binary) ==='
foreach ($patch in $prof.patches) {
	$full   = Join-Path $PrepareRoot ($patch.file -replace '/', '\')
	$search = $patch.search      -replace '\\r\\n', "`r`n"
	$rep    = $patch.replacement -replace '\\r\\n', "`r`n"
	$text   = [System.IO.File]::ReadAllText($full)
	$count  = ([regex]::Matches($text, [regex]::Escape($search))).Count
	if ($count -ne $patch.expectedOccurrences) {
		throw "TextReplace count mismatch: $($patch.file) expected=$($patch.expectedOccurrences) got=$count"
	}
	[System.IO.File]::WriteAllText($full, $text.Replace($search, $rep))
	Write-Host "  PASS $($patch.file) ($count replaced)"
}

Write-Host '=== STEP 4: Verify patched INF hash ==='
$infFull = Join-Path $PrepareRoot 'u0201163.inf'
$infHash = (Get-FileHash $infFull -Algorithm SHA256).Hash
$expHash = ($prof.files | Where-Object { $_.path -eq 'u0201163.inf' }).patchedSha256
if ($infHash -ne $expHash) { throw "Patched INF hash mismatch: expected=$expHash actual=$infHash" }
Write-Host "  PASS u0201163.inf $infHash"

$sysFull = Join-Path $PrepareRoot 'B026079\amdkmdag.sys'
$sysHash = (Get-FileHash $sysFull -Algorithm SHA256).Hash
$sysSig  = Get-AuthenticodeSignature -LiteralPath $sysFull
Write-Host "  amdkmdag.sys hash : $sysHash"
Write-Host "  amdkmdag.sys sig  : $($sysSig.Status) / $($sysSig.SignerCertificate.Subject)"

Write-Host '=== STEP 5: Sign catalog (SkipKernelSigning) ==='
& powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Sign-Package.ps1') `
	-PackageRoot $PrepareRoot `
	-KernelDriverPath $prof.kernelDriverPath `
	-CatalogFile $prof.catalogFile `
	-CertificateSubject $prof.certificateSubject `
	-SkipKernelSigning
if ($LASTEXITCODE -ne 0) { throw "Sign-Package failed: $LASTEXITCODE" }
Write-Host '  PASS signing'

Write-Host '=== STEP 6: Remove current driver ==='
$gpuId  = 'PCI\VEN_1002&DEV_7340&SUBSYS_020F106B&REV_40\6&1821360C&0&00000008'
$curInf = (Get-PnpDeviceProperty -InstanceId $gpuId -KeyName 'DEVPKEY_Device_DriverInfPath' -ErrorAction SilentlyContinue).Data
Write-Host "  Current INF: $curInf"
if ($curInf -match '^oem\d+\.inf$') {
	& pnputil.exe /delete-driver $curInf /uninstall /force | Out-Null
	Write-Host "  Removed $curInf (exit $LASTEXITCODE)"
} else {
	Write-Host '  No OEM driver found, skipping removal'
}

Write-Host '=== STEP 7: Install text-only driver ==='
$pnpOut = & pnputil.exe /add-driver $infFull /install 2>&1 | Out-String
Write-Host $pnpOut
$pnpExit = $LASTEXITCODE
Write-Host "  pnputil exit: $pnpExit"
if ($pnpExit -notin @(0, 259, 3010)) { throw "pnputil failed: $pnpExit" }

Write-Host '=== STEP 8: GPU state after install ==='
Start-Sleep -Seconds 3
$gpu = Get-PnpDevice -Class Display | Where-Object { $_.InstanceId -like '*VEN_1002*DEV_7340*' } | Select-Object -First 1
if ($gpu) {
	$newVer = (Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion' -ErrorAction SilentlyContinue).Data
	$newInf = (Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath' -ErrorAction SilentlyContinue).Data
	Write-Host "  Name   : $($gpu.FriendlyName)"
	Write-Host "  Status : $($gpu.Status) / $($gpu.Problem)"
	Write-Host "  Version: $newVer"
	Write-Host "  INF    : $newInf"
} else {
	Write-Host '  GPU not found after install'
}

Write-Host '=== STEP 9: Set testsigning OFF ==='
& bcdedit /set testsigning off | Out-Null
Write-Host '  testsigning OFF set'

Stop-Transcript | Out-Null

Write-Host ''
Write-Host '--- Rebooting in 10 seconds. To cancel: shutdown /a ---'
Start-Sleep -Seconds 2
shutdown /r /t 10
