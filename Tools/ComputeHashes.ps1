$sysOrig = "C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF\B026079\amdkmdag.sys"
$gcfOrig = "C:\AMD\AMD-Software-Installer\Packages\Drivers\Display2\WT6A_INF\B026079\amdgcf.dat"

$sysOrigHash = (Get-FileHash $sysOrig -Algorithm SHA256).Hash
$gcfOrigHash = (Get-FileHash $gcfOrig -Algorithm SHA256).Hash
Write-Host "amdkmdag.sys original : $sysOrigHash"
Write-Host "amdgcf.dat   original : $gcfOrigHash"

# amdkmdag.sys: offset 338591, 0x79 -> 0xEB
$sysBytes = [System.IO.File]::ReadAllBytes($sysOrig)
Write-Host ("amdkmdag.sys byte@338591 : 0x{0:X2}" -f $sysBytes[338591])
$sysBytes[338591] = 0xEB
$sysTmp = "$env:TEMP\amdkmdag_patched.sys"
[System.IO.File]::WriteAllBytes($sysTmp, $sysBytes)
$sysPatchedHash = (Get-FileHash $sysTmp -Algorithm SHA256).Hash
Write-Host "amdkmdag.sys patched  : $sysPatchedHash"

# amdgcf.dat: insert 3 bytes at offset 342, then int32@0: 170->171
$gcfBytes = [System.IO.File]::ReadAllBytes($gcfOrig)
$int32Before = [System.BitConverter]::ToInt32($gcfBytes, 0)
Write-Host "amdgcf.dat int32@0 before: $int32Before"
$insert = [byte[]]@(0x40, 0x73, 0x40)
$newGcf = New-Object byte[] ($gcfBytes.Length + 3)
[System.Array]::Copy($gcfBytes, 0, $newGcf, 0, 342)
[System.Array]::Copy($insert, 0, $newGcf, 342, 3)
[System.Array]::Copy($gcfBytes, 342, $newGcf, 345, $gcfBytes.Length - 342)
$int32After = [System.BitConverter]::ToInt32($newGcf, 0)
Write-Host "amdgcf.dat int32@0 after insert (before fix): $int32After"
$newInt32Bytes = [System.BitConverter]::GetBytes([int32]171)
[System.Array]::Copy($newInt32Bytes, 0, $newGcf, 0, 4)
$gcfTmp = "$env:TEMP\amdgcf_patched.dat"
[System.IO.File]::WriteAllBytes($gcfTmp, $newGcf)
$gcfPatchedHash = (Get-FileHash $gcfTmp -Algorithm SHA256).Hash
Write-Host "amdgcf.dat   patched  : $gcfPatchedHash"

Write-Host ""
Write-Host "=== Profile 현재값 비교 ==="
Write-Host "radeon-pro-5500m.json amdkmdag patchedSha256: 6B3C6E1E85FD15D0AD0BABC1C32B3D514A3357E2533CA529C8C054648C95073D"
Write-Host "radeon-pro-5500m.json amdgcf   patchedSha256: DA56346B08E7D6A86D94AE6F2A11D366F43C8E8988120D98F29C9B9011699D25"
if($sysPatchedHash -eq "6B3C6E1E85FD15D0AD0BABC1C32B3D514A3357E2533CA529C8C054648C95073D"){ Write-Host "amdkmdag MATCH OK" } else { Write-Host "amdkmdag MISMATCH - profile needs: $sysPatchedHash" }
if($gcfPatchedHash -eq "DA56346B08E7D6A86D94AE6F2A11D366F43C8E8988120D98F29C9B9011699D25"){ Write-Host "amdgcf   MATCH OK" } else { Write-Host "amdgcf   MISMATCH - profile needs: $gcfPatchedHash" }
