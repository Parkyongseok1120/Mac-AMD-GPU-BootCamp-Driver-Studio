param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$KernelDriverPath,
    [Parameter(Mandatory = $true)][string]$CatalogFile,
    [Parameter(Mandatory = $true)][string]$CertificateSubject,
    [switch]$ValidateOnly
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
    foreach ($file in @($kernel, $catalog)) {
        if (-not (Test-Path -LiteralPath $file)) { throw "Signed file not found: $file" }
        $sig = Get-AuthenticodeSignature -LiteralPath $file
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -ne $CertificateSubject) {
            throw "Signature validation failed: $file ($($sig.Status))"
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

$sysSig = Set-AuthenticodeSignature -LiteralPath $kernel -Certificate $cert -HashAlgorithm SHA256
if ($sysSig.Status -ne 'Valid') { throw "Kernel signing failed: $($sysSig.StatusMessage)" }
if (Test-Path -LiteralPath $catalog) { Remove-Item -LiteralPath $catalog -Force }
New-FileCatalog -Path $PackageRoot -CatalogFilePath $catalog -CatalogVersion 2.0 | Out-Null
$catSig = Set-AuthenticodeSignature -LiteralPath $catalog -Certificate $cert -HashAlgorithm SHA256
if ($catSig.Status -ne 'Valid') { throw "Catalog signing failed: $($catSig.StatusMessage)" }

Write-Output "THUMBPRINT=$($cert.Thumbprint)"
