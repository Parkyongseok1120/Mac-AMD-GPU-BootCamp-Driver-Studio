#Requires -RunAsAdministrator
<#
  text-only 프로필 (kernelDriverModified=false) 테스트
  - amdkmdag.sys 미수정
  - testsigning 없이 cert store import만으로 설치
#>
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

$ScriptDir   = "C:\Users\YongseokPark\Documents\Github\Mac-AMD-GPU-BootCamp-Driver-Studio\Scripts"
$ProfilePath = "C:\Users\YongseokPark\Documents\Github\Mac-AMD-GPU-BootCamp-Driver-Studio\Profiles\radeon-pro-5500m-text-only.json"
$SrcRoot     = "C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF"
$PrepareRoot = "C:\AMD\BootCampDriverStudio\Prepared\AMD-26.6.1-textonly-test"

$profile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host "=== STEP 1: Prepared 폴더 초기화 ===" -ForegroundColor Cyan
if (Test-Path $PrepareRoot) { Remove-Item -Recurse -Force -LiteralPath $PrepareRoot }
Copy-Item -Recurse -LiteralPath $SrcRoot -Destination $PrepareRoot
Write-Host "  복사 완료: $PrepareRoot"

Write-Host ""
Write-Host "=== STEP 2: 원본 해시 검증 ===" -ForegroundColor Cyan
foreach ($f in $profile.files) {
	$full = Join-Path $PrepareRoot ($f.path -replace '/', '\')
	if (-not (Test-Path $full)) { throw "파일 없음: $($f.path)" }
	$hash = (Get-FileHash $full -Algorithm SHA256).Hash
	if ($hash -ne $f.sha256) { throw "원본 해시 불일치: $($f.path)`n  expected: $($f.sha256)`n  actual  : $hash" }
	Write-Host "  OK $($f.path)"
}

Write-Host ""
Write-Host "=== STEP 3: 패치 적용 (TextReplace 4개, 바이너리 0%) ===" -ForegroundColor Cyan
foreach ($patch in $profile.patches) {
	$full = Join-Path $PrepareRoot ($patch.file -replace '/', '\')
	Write-Host "  [$($patch.type)] $($patch.file)"
	$text    = [System.IO.File]::ReadAllText($full)
	$search  = $patch.search      -replace '\\r\\n', "`r`n"
	$replace = $patch.replacement -replace '\\r\\n', "`r`n"
	$count   = ([regex]::Matches($text, [regex]::Escape($search))).Count
	if ($count -ne $patch.expectedOccurrences) { throw "TextReplace 예상 횟수 불일치: expected $($patch.expectedOccurrences), found $count" }
	[System.IO.File]::WriteAllText($full, $text.Replace($search, $replace))
	Write-Host "    -> $count 곳 치환 완료"
}

Write-Host ""
Write-Host "=== STEP 4: 패치 후 INF 해시 검증 ===" -ForegroundColor Cyan
$infPath = Join-Path $PrepareRoot "u0201163.inf"
$infHash = (Get-FileHash $infPath -Algorithm SHA256).Hash
$expectedInfHash = ($profile.files | Where-Object { $_.path -eq "u0201163.inf" }).patchedSha256
if ($infHash -ne $expectedInfHash) { throw "INF 패치 해시 불일치`n  expected: $expectedInfHash`n  actual  : $infHash" }
Write-Host "  OK u0201163.inf: $infHash"

$sysPath = Join-Path $PrepareRoot "B026079\amdkmdag.sys"
$sysHash = (Get-FileHash $sysPath -Algorithm SHA256).Hash
Write-Host "  amdkmdag.sys (원본 유지): $sysHash"
$sysSig  = Get-AuthenticodeSignature -LiteralPath $sysPath
Write-Host "  amdkmdag.sys 서명 상태 : $($sysSig.Status) / $($sysSig.SignerCertificate.Subject)"

Write-Host ""
Write-Host "=== STEP 5: 카탈로그 서명 (-SkipKernelSigning) ===" -ForegroundColor Cyan
$signScript = Join-Path $ScriptDir "Sign-Package.ps1"
& powershell -ExecutionPolicy Bypass -File $signScript `
	-PackageRoot $PrepareRoot `
	-KernelDriverPath $profile.kernelDriverPath `
	-CatalogFile $profile.catalogFile `
	-CertificateSubject $profile.certificateSubject `
	-SkipKernelSigning
if ($LASTEXITCODE -ne 0) { throw "서명 실패: exit $LASTEXITCODE" }
Write-Host "  서명 완료"

Write-Host ""
Write-Host "=== STEP 6: 서명 검증 (-SkipKernelSigning -ValidateOnly) ===" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File $signScript `
	-PackageRoot $PrepareRoot `
	-KernelDriverPath $profile.kernelDriverPath `
	-CatalogFile $profile.catalogFile `
	-CertificateSubject $profile.certificateSubject `
	-SkipKernelSigning -ValidateOnly
if ($LASTEXITCODE -ne 0) { throw "서명 검증 실패: exit $LASTEXITCODE" }
Write-Host "  검증 OK"

Write-Host ""
Write-Host "=== STEP 7: testsigning 상태 확인 ===" -ForegroundColor Cyan
$bcd = & bcdedit /enum | Out-String
$tsActive = $bcd -match "(?m)^testsigning\s+(Yes|On|True|1)"
Write-Host "  testsigning 현재 상태: $(if($tsActive){'ON'}else{'OFF'})"

Write-Host ""
Write-Host "=== STEP 8: pnputil 설치 (testsigning 없이) ===" -ForegroundColor Cyan
$infFull = Join-Path $PrepareRoot "u0201163.inf"
Write-Host "  pnputil /add-driver $infFull /install"
$pnpOut = & pnputil.exe /add-driver $infFull /install 2>&1 | Out-String
Write-Host $pnpOut
# 259 = ERROR_NO_MORE_ITEMS: 드라이버 스토어에 추가됐지만 현재 장치가 이미 동일/상위 버전 사용 중 (정상)
if ($LASTEXITCODE -notin @(0, 259, 3010)) { throw "pnputil 실패: exit $LASTEXITCODE" }
$pnpStatus = switch($LASTEXITCODE) {
    0    { "설치 완료" }
    259  { "스토어 등록 완료 (장치는 이미 동일 버전 사용 중)" }
    3010 { "설치 완료 (재부팅 필요)" }
}
Write-Host "  pnputil 완료: $pnpStatus (exit $LASTEXITCODE)"

Write-Host ""
Write-Host "=== STEP 9: 설치 후 GPU 상태 확인 ===" -ForegroundColor Cyan
Start-Sleep -Seconds 3
$gpu = Get-PnpDevice -Class Display | Where-Object { $_.InstanceId -like "*VEN_1002*DEV_7340*" } | Select-Object -First 1
if ($gpu) {
	$newVer = (Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName "DEVPKEY_Device_DriverVersion" -ErrorAction SilentlyContinue).Data
	$newInf = (Get-PnpDeviceProperty -InstanceId $gpu.InstanceId -KeyName "DEVPKEY_Device_DriverInfPath" -ErrorAction SilentlyContinue).Data
	Write-Host "  GPU    : $($gpu.FriendlyName)"
	Write-Host "  Status : $($gpu.Status) / Problem: $($gpu.Problem)"
	Write-Host "  Version: $newVer"
	Write-Host "  INF    : $newInf"
} else {
	Write-Host "  GPU 장치를 찾을 수 없습니다!" -ForegroundColor Red
}

Write-Host ""
if ($LASTEXITCODE -eq 3010) {
	Write-Host "=== 결과: 재부팅 필요 (3010) — 하지만 testsigning 없이 설치됨 ===" -ForegroundColor Yellow
} else {
	Write-Host "=== 결과: 설치 완료 ===" -ForegroundColor Green
}
