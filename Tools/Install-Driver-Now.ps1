#Requires -RunAsAdministrator
<#
.SYNOPSIS
	AMD Radeon Pro 5500M 드라이버 전체 설치 자동화
	원본 파일 -> 패치 -> 서명 -> 설치 전 과정을 수행합니다.
#>
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

$ScriptDir   = "C:\Users\YongseokPark\Documents\Github\Mac-AMD-GPU-BootCamp-Driver-Studio\Scripts"
$ProfilePath = "C:\Users\YongseokPark\Documents\Github\Mac-AMD-GPU-BootCamp-Driver-Studio\Profiles\radeon-pro-5500m.json"
$SrcRoot     = "C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF"
$PrepareRoot = "C:\AMD\BootCampDriverStudio\Prepared\AMD-26.6.1-020f106b-install"

$profile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host ""
Write-Host "=== STEP 1: Prepared 폴더 초기화 ===" -ForegroundColor Cyan
if (Test-Path $PrepareRoot) {
	Remove-Item -Recurse -Force -LiteralPath $PrepareRoot
	Write-Host "  기존 폴더 삭제 완료"
}
Copy-Item -Recurse -LiteralPath $SrcRoot -Destination $PrepareRoot
Write-Host "  원본 복사 완료: $PrepareRoot"

Write-Host ""
Write-Host "=== STEP 2: 원본 파일 해시 검증 ===" -ForegroundColor Cyan
foreach ($f in $profile.files) {
	$rel  = ($f.path -replace '/', '\')
	$full = Join-Path $PrepareRoot $rel
	if (-not (Test-Path $full)) { throw "파일 없음: $full" }
	$hash = (Get-FileHash $full -Algorithm SHA256).Hash
	if ($hash -ne $f.sha256) { throw "원본 해시 불일치: $rel`n  expected: $($f.sha256)`n  actual  : $hash" }
	Write-Host "  OK $rel : $hash"
}

Write-Host ""
Write-Host "=== STEP 3: 패치 적용 ===" -ForegroundColor Cyan
foreach ($patch in $profile.patches) {
	$rel  = ($patch.file -replace '/', '\')
	$full = Join-Path $PrepareRoot $rel
	Write-Host "  [$($patch.type)] $rel"
	switch ($patch.type) {
		'TextReplace' {
			$text    = [System.IO.File]::ReadAllText($full)
			$search  = $patch.search  -replace '\\r\\n', "`r`n"
			$replace = $patch.replacement -replace '\\r\\n', "`r`n"
			$count   = ([regex]::Matches($text, [regex]::Escape($search))).Count
			if ($count -ne $patch.expectedOccurrences) {
				throw "TextReplace: expected $($patch.expectedOccurrences) occurrences, found $count in $rel"
			}
			$text = $text.Replace($search, $replace)
			[System.IO.File]::WriteAllText($full, $text)
			Write-Host "    -> $count 곳 치환 완료"
		}
		'BinaryReplace' {
			$bytes   = [System.IO.File]::ReadAllBytes($full)
			$expByte = [Convert]::ToByte($patch.expectedHex, 16)
			$repByte = [Convert]::ToByte($patch.replacementHex, 16)
			if ($bytes[$patch.offset] -ne $expByte) {
				throw "BinaryReplace: offset $($patch.offset) expected 0x$($patch.expectedHex), found 0x$('{0:X2}' -f $bytes[$patch.offset])"
			}
			$bytes[$patch.offset] = $repByte
			[System.IO.File]::WriteAllBytes($full, $bytes)
			Write-Host "    -> offset $($patch.offset): 0x$($patch.expectedHex) -> 0x$($patch.replacementHex)"
		}
		'BinaryInsert' {
			$bytes    = [System.IO.File]::ReadAllBytes($full)
			$insBytes = [byte[]]($patch.dataHex -replace '(..)','$1 ' -split ' ' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) })
			$newBuf   = New-Object byte[] ($bytes.Length + $insBytes.Length)
			[System.Array]::Copy($bytes, 0, $newBuf, 0, $patch.offset)
			[System.Array]::Copy($insBytes, 0, $newBuf, $patch.offset, $insBytes.Length)
			[System.Array]::Copy($bytes, $patch.offset, $newBuf, $patch.offset + $insBytes.Length, $bytes.Length - $patch.offset)
			foreach ($upd in $patch.int32Updates) {
				$cur = [System.BitConverter]::ToInt32($newBuf, $upd.offset)
				if ($cur -ne $upd.expectedValue) { throw "int32Update: offset $($upd.offset) expected $($upd.expectedValue), found $cur" }
				[System.Array]::Copy([System.BitConverter]::GetBytes([int32]$upd.value), 0, $newBuf, $upd.offset, 4)
			}
			[System.IO.File]::WriteAllBytes($full, $newBuf)
			Write-Host "    -> $($insBytes.Length) bytes 삽입 완료 (offset $($patch.offset))"
		}
	}
}

Write-Host ""
Write-Host "=== STEP 4: 패치 후 해시 검증 ===" -ForegroundColor Cyan
foreach ($f in $profile.files) {
	if (-not $f.patchedSha256) { Write-Host "  SKIP $($f.path) (patchedSha256 없음 - 원본 유지)"; continue }
	$rel  = ($f.path -replace '/', '\')
	$full = Join-Path $PrepareRoot $rel
	$hash = (Get-FileHash $full -Algorithm SHA256).Hash
	if ($hash -ne $f.patchedSha256) { throw "패치 후 해시 불일치: $rel`n  expected: $($f.patchedSha256)`n  actual  : $hash" }
	Write-Host "  OK $rel : $hash"
}

Write-Host ""
Write-Host "=== STEP 5: 로컬 테스트 서명 ===" -ForegroundColor Cyan
$signScript = Join-Path $ScriptDir "Sign-Package.ps1"
& powershell -ExecutionPolicy Bypass -File $signScript `
	-PackageRoot $PrepareRoot `
	-KernelDriverPath $profile.kernelDriverPath `
	-CatalogFile $profile.catalogFile `
	-CertificateSubject $profile.certificateSubject
if ($LASTEXITCODE -ne 0) { throw "Sign-Package.ps1 실패: exit $LASTEXITCODE" }
Write-Host "  서명 완료"

Write-Host ""
Write-Host "=== STEP 6: 서명 검증 ===" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File $signScript `
	-PackageRoot $PrepareRoot `
	-KernelDriverPath $profile.kernelDriverPath `
	-CatalogFile $profile.catalogFile `
	-CertificateSubject $profile.certificateSubject `
	-ValidateOnly
if ($LASTEXITCODE -ne 0) { throw "Sign-Package.ps1 -ValidateOnly 실패: exit $LASTEXITCODE" }
Write-Host "  서명 검증 OK"

Write-Host ""
Write-Host "=== STEP 7: 테스트 서명 부팅 활성화 ===" -ForegroundColor Cyan
$bridgeScript = Join-Path $ScriptDir "System-Bridge.ps1"
& powershell -ExecutionPolicy Bypass -File $bridgeScript `
	-Action EnableTestSigning `
	-ProfilePath $ProfilePath
if ($LASTEXITCODE -ne 0) { throw "EnableTestSigning 실패: exit $LASTEXITCODE" }

Write-Host ""
Write-Host "=== STEP 8: 현재 TestSigning 활성 여부 확인 ===" -ForegroundColor Cyan
$bcdOut = & bcdedit /enum | Out-String
$tsActive = $bcdOut -match "testsigning\s+(Yes|On|True|1)"
if (-not $tsActive) {
	Write-Host ""
	Write-Host "!!! 테스트 서명이 아직 비활성 상태입니다." -ForegroundColor Yellow
	Write-Host "!!! 재부팅 후 이 스크립트를 다시 실행하면 설치가 진행됩니다." -ForegroundColor Yellow
	Write-Host "    재부팅 명령: shutdown /r /t 10" -ForegroundColor Yellow
	exit 0
}

Write-Host ""
Write-Host "=== STEP 9: 드라이버 설치 ===" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File $bridgeScript `
	-Action Install `
	-ProfilePath $ProfilePath `
	-PackageRoot $PrepareRoot
if ($LASTEXITCODE -ne 0) { throw "드라이버 설치 실패: exit $LASTEXITCODE" }

Write-Host ""
Write-Host "=== 설치 완료 ===" -ForegroundColor Green
Write-Host "재부팅하면 드라이버가 완전히 적용됩니다."
