param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$KernelDriverPath,
    [Parameter(Mandatory = $true)][string]$CatalogFile,
    [Parameter(Mandatory = $true)][string]$CertificateSubject,
    [switch]$ValidateOnly,
    [switch]$SkipKernelSigning
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

function Resolve-SafeChild([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -split '[\\/]' -contains '..') {
        throw "Unsafe package-relative path: $Relative"
    }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath((Join-Path $Root ($Relative -replace '/', '\')))
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped package root: $Relative"
    }
    return $full
}

$kernel = Resolve-SafeChild $PackageRoot $KernelDriverPath
$catalog = Resolve-SafeChild $PackageRoot $CatalogFile
if (-not (Test-Path -LiteralPath $kernel)) { throw "Kernel driver not found: $kernel" }

if ($ValidateOnly) {
    if (-not (Test-Path -LiteralPath $catalog)) { throw "Signed file not found: $catalog" }
    $catSig = Get-AuthenticodeSignature -LiteralPath $catalog
    if ($catSig.Status -ne 'Valid' -or $catSig.SignerCertificate.Subject -ne $CertificateSubject) {
        throw "Signature validation failed: $catalog ($($catSig.Status))"
    }
    if ($SkipKernelSigning) {
        if (-not (Test-Path -LiteralPath $kernel)) { throw "Signed file not found: $kernel" }
        $kernelSig = Get-AuthenticodeSignature -LiteralPath $kernel
        if ($kernelSig.Status -ne 'Valid') {
            throw "Original kernel driver signature is invalid: $kernel ($($kernelSig.Status))"
        }
    } else {
        if (-not (Test-Path -LiteralPath $kernel)) { throw "Signed file not found: $kernel" }
        $kernelSig = Get-AuthenticodeSignature -LiteralPath $kernel
        if ($kernelSig.Status -ne 'Valid' -or $kernelSig.SignerCertificate.Subject -ne $CertificateSubject) {
            throw "Signature validation failed: $kernel ($($kernelSig.Status))"
        }
    }
    Write-Output 'SIGNATURES=Valid'
    exit 0
}

$cert = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.Subject -eq $CertificateSubject -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date).AddDays(30) } |
    Sort-Object NotAfter -Descending | Select-Object -First 1
if (-not $cert) {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $CertificateSubject `
        -CertStoreLocation 'Cert:\LocalMachine\My' -KeyAlgorithm RSA -KeyLength 3072 `
        -HashAlgorithm SHA256 -KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(10)
}

$cer = Join-Path $env:TEMP 'AMD-BootCamp-Driver-Studio.cer'
Export-Certificate -Cert $cert -FilePath $cer -Force | Out-Null
Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null

if (-not $SkipKernelSigning) {
    $sysSig = Set-AuthenticodeSignature -LiteralPath $kernel -Certificate $cert -HashAlgorithm SHA256
    if ($sysSig.Status -ne 'Valid') { throw "Kernel signing failed: $($sysSig.StatusMessage)" }
}
if (Test-Path -LiteralPath $catalog) { Remove-Item -LiteralPath $catalog -Force }
New-FileCatalog -Path $PackageRoot -CatalogFilePath $catalog -CatalogVersion 2.0 | Out-Null
$catSig = Set-AuthenticodeSignature -LiteralPath $catalog -Certificate $cert -HashAlgorithm SHA256
if ($catSig.Status -ne 'Valid') { throw "Catalog signing failed: $($catSig.StatusMessage)" }

Write-Output "THUMBPRINT=$($cert.Thumbprint)"
