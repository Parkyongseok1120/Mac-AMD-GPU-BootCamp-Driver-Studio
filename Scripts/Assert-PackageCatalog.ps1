param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$CatalogFile,
    [Parameter(Mandatory = $true)][string]$InstallationMode,
    [string]$CertificateSubject = 'CN=Local AMD BootCamp Test Driver'
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

$catalog = Resolve-SafeChild $PackageRoot $CatalogFile
if (-not (Test-Path -LiteralPath $catalog)) { throw "Catalog not found: $catalog" }
$sig = Get-AuthenticodeSignature -LiteralPath $catalog
$isLocal = ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -eq $CertificateSubject)

if (-not $isLocal) {
    throw "Catalog signature validation failed: $catalog ($($sig.Status))"
}
Write-Output 'CATALOG_POLICY=Local'
exit 0
