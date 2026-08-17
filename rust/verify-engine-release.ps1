param(
  [string]$ReleaseRoot = (Join-Path $PSScriptRoot '..\third_party\uniclipboard-engine\v1.1.0-rc.3')
)

$ErrorActionPreference = 'Stop'

function Get-Sha256Hex {
  param([string]$Path)

  $stream = [System.IO.File]::OpenRead($Path)
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = $sha256.ComputeHash($stream)
    return ([System.BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha256.Dispose()
    $stream.Dispose()
  }
}

$releaseRootPath = [System.IO.Path]::GetFullPath($ReleaseRoot)
$metadataPath = Join-Path $releaseRootPath 'engine-release.json'

if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
  throw "Engine release metadata not found: $metadataPath"
}

$release = Get-Content -Raw -LiteralPath $metadataPath | ConvertFrom-Json
if ($release.schemaVersion -ne 1) {
  throw "Unsupported Engine release metadata schema: $($release.schemaVersion)"
}

foreach ($asset in $release.files) {
  $assetPath = Join-Path $releaseRootPath $asset.name
  if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
    throw "Required Engine asset not found: $assetPath"
  }
  $assetInfo = Get-Item -LiteralPath $assetPath
  if ($assetInfo.Length -ne [long]$asset.size) {
    throw "Engine asset size mismatch for $($asset.name): expected $($asset.size), got $($assetInfo.Length)"
  }
  $actualHash = Get-Sha256Hex -Path $assetPath
  if ($actualHash -ne $asset.sha256) {
    throw "Engine asset SHA-256 mismatch for $($asset.name): expected $($asset.sha256), got $actualHash"
  }
}

$manifestPath = Join-Path $releaseRootPath 'release-manifest.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.release.version -ne $release.version) {
  throw "Engine version mismatch: metadata=$($release.version), manifest=$($manifest.release.version)"
}
if ($manifest.release.commit -ne $release.sourceCommit) {
  throw "Engine source commit mismatch: metadata=$($release.sourceCommit), manifest=$($manifest.release.commit)"
}
if ($manifest.compatibility.minimumSystems.harmonyosApi -ne $release.minimumHarmonyOsApi) {
  throw 'Engine HarmonyOS minimum API does not match the pinned metadata'
}

$version = (Get-Content -Raw -LiteralPath (Join-Path $releaseRootPath 'version.txt')).Trim()
$sourceCommit = (Get-Content -Raw -LiteralPath (Join-Path $releaseRootPath 'source-commit.txt')).Trim()
if ($version -ne $release.version -or $sourceCommit -ne $release.sourceCommit) {
  throw 'Engine version.txt or source-commit.txt does not match the pinned metadata'
}

$harPath = Join-Path $releaseRootPath 'UniClipboardEngine.har'
$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$extractionRoot = Join-Path $temporaryBase ("uniclipboard-engine-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $extractionRoot | Out-Null
try {
  & tar -xf $harPath -C $extractionRoot
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to extract Engine HAR; tar exited with code $LASTEXITCODE"
  }

  $packagePath = Join-Path $extractionRoot 'package\oh-package.json5'
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw 'Engine HAR does not contain package/oh-package.json5'
  }
  $package = Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json
  if ($package.name -ne '@uniclipboard/engine' -or $package.version -ne $release.packageVersion) {
    throw 'Engine HAR package name or version does not match the pinned metadata'
  }
  if ($package.compatibleSdkVersion -ne $release.minimumHarmonyOsApi) {
    throw 'Engine HAR compatibleSdkVersion does not match the pinned metadata'
  }

  $entriesToCheck = @($release.embeddedLibrary, $release.embeddedDeclaration)
  foreach ($entryMetadata in $entriesToCheck) {
    $relativeEntryPath = $entryMetadata.path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $entryPath = Join-Path $extractionRoot $relativeEntryPath
    if (-not (Test-Path -LiteralPath $entryPath -PathType Leaf)) {
      throw "Engine HAR entry not found: $($entryMetadata.path)"
    }
    $entryInfo = Get-Item -LiteralPath $entryPath
    if ($entryInfo.Length -ne [long]$entryMetadata.size) {
      throw "Engine HAR entry size mismatch for $($entryMetadata.path)"
    }
    $entryHash = Get-Sha256Hex -Path $entryPath
    if ($entryHash -ne $entryMetadata.sha256) {
      throw "Engine HAR entry SHA-256 mismatch for $($entryMetadata.path)"
    }
  }
} finally {
  $resolvedExtractionRoot = [System.IO.Path]::GetFullPath($extractionRoot)
  if ($resolvedExtractionRoot.StartsWith($temporaryBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedExtractionRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Output "Verified UniClipboard Engine $($release.version) ($($release.sourceCommit))."
Write-Output "Release: $($release.releaseUrl)"
