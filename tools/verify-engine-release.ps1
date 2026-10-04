param(
  # 必须与 oh-package.json5 / common-oh-package.json5 里引用的 HAR 版本一致，
  # 否则这个校验会在验一个已经不再发布的旧产物。
  [string]$ReleaseRoot = (Join-Path $PSScriptRoot '..\third_party\uniclipboard-engine\v1.1.0-rc.22-harmony')
)

$ErrorActionPreference = 'Stop'

function Read-TarBlock {
  param([System.IO.Stream]$Stream)

  $bytes = [byte[]]::new(512)
  $offset = 0
  while ($offset -lt $bytes.Length) {
    $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset)
    if ($read -eq 0) {
      if ($offset -eq 0) { return $null }
      throw 'Unexpected end of Engine HAR tar header'
    }
    $offset += $read
  }
  return ,$bytes
}

function Consume-TarData {
  param(
    [System.IO.Stream]$Stream,
    [long]$Count,
    [System.IO.Stream]$Capture
  )

  $buffer = [byte[]]::new(65536)
  $remaining = $Count
  while ($remaining -gt 0) {
    $requested = [int][Math]::Min([long]$buffer.Length, $remaining)
    $read = $Stream.Read($buffer, 0, $requested)
    if ($read -eq 0) { throw 'Unexpected end of Engine HAR tar entry' }
    if ($null -ne $Capture) { $Capture.Write($buffer, 0, $read) }
    $remaining -= $read
  }
  if ($null -eq $Capture) { return $null }
  $Capture.Position = 0
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha256.ComputeHash($Capture))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha256.Dispose()
  }
}
function Get-NormalizedTextSha256Hex {
  param([string]$Path)

  $content = [System.IO.File]::ReadAllText($Path)
  $normalizedContent = $content.Replace("`r`n", "`n").Replace("`r", "`n")
  $encoding = [System.Text.UTF8Encoding]::new($false)
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = $sha256.ComputeHash($encoding.GetBytes($normalizedContent))
    return ([System.BitConverter]::ToString($bytes)).Replace([string][char]45, [string]::Empty).ToLowerInvariant()
  } finally {
    $sha256.Dispose()
  }
}
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
$embeddedMetadata = @($release.embeddedLibraries) + @($release.embeddedDeclaration)
$embeddedByPath = @{}
foreach ($entryMetadata in $embeddedMetadata) {
  $embeddedByPath[$entryMetadata.path.Replace('\', '/')] = $entryMetadata
}
$embeddedResults = @{}
$packageJson = $null
$fileStream = [System.IO.File]::OpenRead($harPath)
$gzipStream = [System.IO.Compression.GZipStream]::new(
  $fileStream, [System.IO.Compression.CompressionMode]::Decompress, $true)
$ascii = [System.Text.Encoding]::ASCII
try {
  while ($null -ne ($header = Read-TarBlock -Stream $gzipStream)) {
    $isEndBlock = $true
    foreach ($value in $header) {
      if ($value -ne 0) { $isEndBlock = $false; break }
    }
    if ($isEndBlock) { break }

    $name = $ascii.GetString($header, 0, 100).TrimEnd([char]0)
    $prefix = ''
    $magic = $ascii.GetString($header, 257, 6).TrimEnd([char]0)
    if ($magic.StartsWith('ustar')) {
      $entryName = if ([string]::IsNullOrWhiteSpace($prefix)) { $name } else { "$prefix/$name" }
    } else {
      $entryName = $name
    }
    $sizeText = $ascii.GetString($header, 124, 12).Trim([char[]]@([char]0, [char]32))
    if ([string]::IsNullOrWhiteSpace($sizeText)) {
      $entrySize = 0L
    } elseif ($sizeText -match '^[0-7]+$') {
      $entrySize = [Convert]::ToInt64($sizeText, 8)
    } else {
      throw "Invalid tar entry size for $entryName"
    }

    $capture = $null
    if ($entryName -eq 'package/oh-package.json5') {
      $capture = [System.IO.MemoryStream]::new()
    } elseif ($embeddedByPath.ContainsKey($entryName)) {
      $capture = [System.IO.MemoryStream]::new()
    }
    if ($null -ne $capture -or $embeddedByPath.ContainsKey($entryName)) {
      $actualHash = Consume-TarData -Stream $gzipStream -Count $entrySize -Capture $capture
      if ($embeddedByPath.ContainsKey($entryName)) {
        $embeddedResults[$entryName] = [pscustomobject]@{ Size = $entrySize; Sha256 = $actualHash }
      }
      if ($entryName -eq 'package/oh-package.json5') {
        $packageJson = [System.Text.Encoding]::UTF8.GetString($capture.ToArray())
      }
      if ($null -ne $capture) { $capture.Dispose() }
    } else {
      $null = Consume-TarData -Stream $gzipStream -Count $entrySize -Capture $null
    }
    $padding = (512 - ($entrySize % 512)) % 512
    if ($padding -gt 0) {
      $null = Consume-TarData -Stream $gzipStream -Count $padding -Capture $null
    }
  }
} finally {
  $gzipStream.Dispose()
  $fileStream.Dispose()
}
if ([string]::IsNullOrWhiteSpace($packageJson)) {
  throw 'Engine HAR does not contain package/oh-package.json5'
}
$package = $packageJson | ConvertFrom-Json
if ($package.name -ne '@uniclipboard/engine' -or $package.version -ne $release.packageVersion) {
  throw 'Engine HAR package name or version does not match the pinned metadata'
}
if ($package.compatibleSdkVersion -ne $release.minimumHarmonyOsApi) {
  throw 'Engine HAR compatibleSdkVersion does not match the pinned metadata'
}
foreach ($entryMetadata in $embeddedMetadata) {
  $entryName = $entryMetadata.path.Replace('\', '/')
  if (-not $embeddedResults.ContainsKey($entryName)) {
    throw "Engine HAR entry not found: $($entryMetadata.path)"
  }
  $entryResult = $embeddedResults[$entryName]
  if ($entryResult.Size -ne [long]$entryMetadata.size) {
    throw "Engine HAR entry size mismatch for $($entryMetadata.path)"
  }
  if ($entryResult.Sha256 -ne $entryMetadata.sha256) {
    throw "Engine HAR entry SHA-256 mismatch for $($entryMetadata.path): expected $($entryMetadata.sha256), got $($entryResult.Sha256)"
  }
}

if ($null -ne $release.harmonyAdaptation -and -not [string]::IsNullOrWhiteSpace($release.harmonyAdaptation.patch)) {
  $patchPath = Join-Path $releaseRootPath $release.harmonyAdaptation.patch
  if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf)) {
    throw "Harmony adapter patch not found: $patchPath"
  }
  $patchHash = Get-Sha256Hex -Path $patchPath
  if ($patchHash -ne $release.harmonyAdaptation.patchSha256) {
    throw 'Harmony adapter patch SHA-256 does not match the pinned metadata'
  }
}

if ($null -ne $release.harmonyAdaptation -and -not [string]::IsNullOrWhiteSpace($release.harmonyAdaptation.script)) {
  $adaptationScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) $release.harmonyAdaptation.script
  if (-not (Test-Path -LiteralPath $adaptationScriptPath -PathType Leaf)) {
    throw "Harmony adaptation script not found: $adaptationScriptPath"
  }
  $adaptationScriptHash = Get-NormalizedTextSha256Hex -Path $adaptationScriptPath
  if ($adaptationScriptHash -ne $release.harmonyAdaptation.scriptSha256) {
    throw 'Harmony adaptation script SHA-256 does not match the pinned metadata'
  }
}
Write-Output "Verified UniClipboard Engine $($release.version) ($($release.sourceCommit))."
if ([string]::IsNullOrWhiteSpace($release.releaseUrl)) {
  Write-Output 'Release URL is intentionally unset until the pinned Engine commit is published.'
} else {
  Write-Output "Release: $($release.releaseUrl)"
}
