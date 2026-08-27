param(
  [Parameter(Mandatory = $true)]
  [string]$EngineRoot,
  [Parameter(Mandatory = $true)]
  [string]$BaseHarPath,
  [Parameter(Mandatory = $true)]
  [string]$Arm64Library,
  [Parameter(Mandatory = $true)]
  [string]$X86Library,
  [Parameter(Mandatory = $true)]
  [string]$SourceCommit,
  [string]$Destination
)

$ErrorActionPreference = 'Stop'

$version = 'v1.1.0-rc.7'
$packageVersion = '1.1.0-rc.7'
$destination = if ([string]::IsNullOrWhiteSpace($Destination)) {
  Join-Path $PSScriptRoot '..\third_party\uniclipboard-engine\v1.1.0-rc.7'
} else {
  $Destination
}
$destination = [System.IO.Path]::GetFullPath($destination)
$engineRootPath = [System.IO.Path]::GetFullPath($EngineRoot)
$baseHarPathValue = [System.IO.Path]::GetFullPath($BaseHarPath)
$arm64LibraryPath = [System.IO.Path]::GetFullPath($Arm64Library)
$x86LibraryPath = [System.IO.Path]::GetFullPath($X86Library)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

if (Test-Path -LiteralPath $destination) {
  throw "Refusing to overwrite immutable Engine directory: $destination"
}
if ((& git -C $engineRootPath rev-parse HEAD).Trim() -ne $SourceCommit) {
  throw 'Engine checkout does not match the pinned rc.7 source commit'
}
foreach ($requiredPath in @($baseHarPathValue, $arm64LibraryPath, $x86LibraryPath)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Required Engine input not found: $requiredPath"
  }
}

function Get-Sha256Hex {
  param([Parameter(Mandatory = $true)][string]$Path)

  $stream = [System.IO.File]::OpenRead($Path)
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha256.Dispose()
    $stream.Dispose()
  }
}

function Write-Utf8File {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )

  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Replace-AsciiSequence {
  param(
    [Parameter(Mandatory = $true)][byte[]]$Bytes,
    [Parameter(Mandatory = $true)][string]$OldText,
    [Parameter(Mandatory = $true)][string]$NewText
  )

  $oldBytes = [System.Text.Encoding]::ASCII.GetBytes($OldText)
  $newBytes = [System.Text.Encoding]::ASCII.GetBytes($NewText)
  if ($oldBytes.Length -ne $newBytes.Length) {
    throw "Cannot rewrite bytecode package version with a different length: $OldText -> $NewText"
  }

  $matchCount = 0
  for ($index = 0; $index -le $Bytes.Length - $oldBytes.Length; $index++) {
    $matches = $true
    for ($offset = 0; $offset -lt $oldBytes.Length; $offset++) {
      if ($Bytes[$index + $offset] -ne $oldBytes[$offset]) {
        $matches = $false
        break
      }
    }
    if (-not $matches) {
      continue
    }

    [System.Array]::Copy($newBytes, 0, $Bytes, $index, $newBytes.Length)
    $matchCount++
    $index += $oldBytes.Length - 1
  }

  return [ordered]@{
    bytes = $Bytes
    matches = $matchCount
  }
}

function Get-AsciiSequenceCount {
  param(
    [Parameter(Mandatory = $true)][byte[]]$Bytes,
    [Parameter(Mandatory = $true)][string]$Text
  )

  $pattern = [System.Text.Encoding]::ASCII.GetBytes($Text)
  $matchCount = 0
  for ($index = 0; $index -le $Bytes.Length - $pattern.Length; $index++) {
    $matches = $true
    for ($offset = 0; $offset -lt $pattern.Length; $offset++) {
      if ($Bytes[$index + $offset] -ne $pattern[$offset]) {
        $matches = $false
        break
      }
    }
    if ($matches) {
      $matchCount++
      $index += $pattern.Length - 1
    }
  }
  return $matchCount
}

function Get-HarEntryMetadata {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$EntryName
  )

  $fileStream = [System.IO.File]::OpenRead($Path)
  $gzipStream = [System.IO.Compression.GZipStream]::new(
    $fileStream, [System.IO.Compression.CompressionMode]::Decompress)
  $reader = [System.Formats.Tar.TarReader]::new($gzipStream)
  try {
    while ($entry = $reader.GetNextEntry()) {
      if ($entry.Name -eq $EntryName) {
        if ($null -eq $entry.DataStream) {
          throw "HAR entry has no data: $EntryName"
        }
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
          $hash = ([System.BitConverter]::ToString($sha256.ComputeHash($entry.DataStream))).Replace('-', '').ToLowerInvariant()
        } finally {
          $sha256.Dispose()
        }
        return [ordered]@{
          path = $EntryName
          sha256 = $hash
          size = [long]$entry.Length
        }
      }
    }
  } finally {
    $reader.Dispose()
    $gzipStream.Dispose()
    $fileStream.Dispose()
  }
  throw "Required HAR entry not found: $EntryName"
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
  ("uniclipboard-engine-rc7-" + [System.Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $temporaryRoot 'package'
$harBuildPath = Join-Path $temporaryRoot 'UniClipboardEngine.har'
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

try {
  & tar.exe -xzf $baseHarPathValue -C $temporaryRoot
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to extract base Engine HAR; tar exited with code $LASTEXITCODE"
  }

  $packageManifestPath = Join-Path $packageRoot 'oh-package.json5'
  $packageDeclarationPath = Join-Path $packageRoot 'src\main\cpp\types\libuc_ohos_napi\index.d.ts'
  if (-not (Test-Path -LiteralPath $packageManifestPath -PathType Leaf)) {
    throw 'Base HAR does not contain package/oh-package.json5'
  }
  if (-not (Test-Path -LiteralPath $packageDeclarationPath -PathType Leaf)) {
    throw 'Base HAR does not contain the native declaration file'
  }

  $packageManifest = [System.IO.File]::ReadAllText($packageManifestPath)
  $baseVersionMatch = [regex]::Match(
    $packageManifest,
    '(["'']version["'']\s*:\s*["''])([^"'']+)(["''])',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if (-not $baseVersionMatch.Success) {
    throw 'Unable to read the Engine package version from the base HAR'
  }
  $basePackageVersion = $baseVersionMatch.Groups[2].Value
  if ($basePackageVersion -eq $packageVersion) {
    $updatedManifest = $packageManifest
  } else {
    $updatedManifest = [regex]::Replace(
      $packageManifest,
      '(["'']version["'']\s*:\s*["''])[^"'']+(["''])',
      { param($match) $match.Groups[1].Value + $packageVersion + $match.Groups[2].Value },
      1)
    if ($updatedManifest -eq $packageManifest) {
      throw 'Unable to update the Engine package version in the base HAR'
    }
  }
  Write-Utf8File -Path $packageManifestPath -Content $updatedManifest

  # HAR bytecode keeps the package version in its module records. Keep it in
  # sync with oh-package.json5 or the host will fail during module loading.
  $moduleBytecodePath = Join-Path $packageRoot 'ets\modules.abc'
  if (-not (Test-Path -LiteralPath $moduleBytecodePath -PathType Leaf)) {
    throw 'Base HAR does not contain ets/modules.abc'
  }
  $moduleBytecode = [System.IO.File]::ReadAllBytes($moduleBytecodePath)
  if ($basePackageVersion -eq $packageVersion) {
    $replacement = [ordered]@{ bytes = $moduleBytecode; matches = 0 }
  } else {
    $replacement = Replace-AsciiSequence -Bytes $moduleBytecode `
      -OldText $basePackageVersion -NewText $packageVersion
    if ($replacement.matches -eq 0) {
      throw "Unable to update the Engine module bytecode version from $basePackageVersion"
    }
  }
  [System.IO.File]::WriteAllBytes($moduleBytecodePath, $replacement.bytes)
  if ($basePackageVersion -ne $packageVersion -and
      (Get-AsciiSequenceCount -Bytes $replacement.bytes -Text $basePackageVersion) -ne 0) {
    throw "Engine module bytecode still contains the base version $basePackageVersion"
  }

  $arm64Destination = Join-Path $packageRoot 'libs\arm64-v8a\libuc_ohos_napi.so'
  $x86Destination = Join-Path $packageRoot 'libs\x86_64\libuc_ohos_napi.so'
  New-Item -ItemType Directory -Path (Split-Path -Parent $arm64Destination) -Force | Out-Null
  New-Item -ItemType Directory -Path (Split-Path -Parent $x86Destination) -Force | Out-Null
  Copy-Item -LiteralPath $arm64LibraryPath -Destination $arm64Destination -Force
  Copy-Item -LiteralPath $x86LibraryPath -Destination $x86Destination -Force
  Copy-Item -LiteralPath (Join-Path $engineRootPath 'bindings\uc-ohos-napi\ohos\index.d.ts') `
    -Destination $packageDeclarationPath -Force

  & tar.exe -czf $harBuildPath -C $temporaryRoot 'package'
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to create rc.7 Engine HAR; tar exited with code $LASTEXITCODE"
  }

  New-Item -ItemType Directory -Path $destination | Out-Null
  Copy-Item -LiteralPath $harBuildPath -Destination (Join-Path $destination 'UniClipboardEngine.har')
} finally {
  if (Test-Path -LiteralPath $temporaryRoot) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}

$harDestination = Join-Path $destination 'UniClipboardEngine.har'
$declarationDestination = Join-Path $destination 'index.d.ts'
$licenseDestination = Join-Path $destination 'LICENSE'
Copy-Item -LiteralPath (Join-Path $engineRootPath 'bindings\uc-ohos-napi\ohos\index.d.ts') -Destination $declarationDestination
Copy-Item -LiteralPath (Join-Path $engineRootPath 'LICENSE') -Destination $licenseDestination

$harHash = Get-Sha256Hex -Path $harDestination
$arm64Hash = Get-Sha256Hex -Path $arm64LibraryPath
$x86Hash = Get-Sha256Hex -Path $x86LibraryPath
$declarationHash = Get-Sha256Hex -Path $declarationDestination
Write-Utf8File -Path (Join-Path $destination 'UniClipboardEngine.har.checksum.txt') `
  -Content "$harHash  UniClipboardEngine.har`n"
Write-Utf8File -Path (Join-Path $destination 'uc-ohos-napi.checksum.txt') `
  -Content "$arm64Hash  arm64-v8a/libuc_ohos_napi.so`n"
Write-Utf8File -Path (Join-Path $destination 'uc-ohos-napi-x86_64.checksum.txt') `
  -Content "$x86Hash  x86_64/libuc_ohos_napi.so`n"
Write-Utf8File -Path (Join-Path $destination 'version.txt') -Content "$version`n"
Write-Utf8File -Path (Join-Path $destination 'source-commit.txt') -Content "$SourceCommit`n"

$metadataJson = & cargo metadata --manifest-path (Join-Path $engineRootPath 'Cargo.toml') --locked --format-version 1
if ($LASTEXITCODE -ne 0) {
  throw "cargo metadata failed with exit code $LASTEXITCODE"
}
$metadata = $metadataJson | ConvertFrom-Json
$licenses = @($metadata.packages | ForEach-Object {
  [ordered]@{
    name = $_.name
    version = $_.version
    license = if ($null -eq $_.license) { 'UNKNOWN' } else { $_.license }
    source = if ($null -eq $_.source) { 'workspace' } else { $_.source }
  }
} | Sort-Object { "$($_.name)@$($_.version)" })
$licenseInventory = [ordered]@{ schemaVersion = 1; packages = $licenses }
Write-Utf8File -Path (Join-Path $destination 'dependency-licenses.json') `
  -Content (($licenseInventory | ConvertTo-Json -Depth 8) + "`n")

$cargoLockPath = Join-Path $engineRootPath 'Cargo.lock'
$manifest = [ordered]@{
  schemaVersion = 1
  release = [ordered]@{
    version = $version
    commit = $SourceCommit
    rustToolchain = ((& rustc --version).Trim() -split ' ')[1]
    cargoLockSha256 = Get-Sha256Hex -Path $cargoLockPath
  }
  generators = [ordered]@{
    napi = '2.16.17'
    napiBuild = '2.3.2'
    napiDerive = '2.16.13'
    arkts = 'napi-rs 2.16.17'
  }
  compatibility = [ordered]@{
    p2pProtocols = @('pairing/1', 'presence/0', 'clipboard/0', 'active-clipboard/0',
      'active-clipboard-pull/0', 'transfer-progress/0', 'iroh-blobs')
    database = 'Diesel SQLite embedded migrations'
    minimumSystems = [ordered]@{ harmonyosApi = 24 }
  }
  deviceMatrix = [ordered]@{
    harmonyos = [ordered]@{
      status = 'built'
      architectures = @('arm64-v8a', 'x86_64')
      reason = 'Engine network settings bridge packaged for physical devices and the API 24 x86_64 simulator'
    }
  }
  artifacts = @(
    [ordered]@{ name = 'UniClipboardEngine.har'; platform = 'harmonyos'; architectures = @('arm64-v8a', 'x86_64'); sha256 = $harHash; size = (Get-Item $harDestination).Length },
    [ordered]@{ name = 'index.d.ts'; platform = 'harmonyos'; architectures = @(); sha256 = $declarationHash; size = (Get-Item $declarationDestination).Length },
    [ordered]@{ name = 'LICENSE'; platform = 'source'; architectures = @(); sha256 = Get-Sha256Hex -Path $licenseDestination; size = (Get-Item $licenseDestination).Length },
    [ordered]@{ name = 'source-commit.txt'; platform = 'source'; architectures = @(); sha256 = Get-Sha256Hex -Path (Join-Path $destination 'source-commit.txt'); size = (Get-Item (Join-Path $destination 'source-commit.txt')).Length },
    [ordered]@{ name = 'version.txt'; platform = 'source'; architectures = @(); sha256 = Get-Sha256Hex -Path (Join-Path $destination 'version.txt'); size = (Get-Item (Join-Path $destination 'version.txt')).Length }
  )
}
$manifestPath = Join-Path $destination 'release-manifest.json'
Write-Utf8File -Path $manifestPath -Content (($manifest | ConvertTo-Json -Depth 10) + "`n")

$embeddedArm64 = Get-HarEntryMetadata -Path $harDestination `
  -EntryName 'package/libs/arm64-v8a/libuc_ohos_napi.so'
$embeddedX86 = Get-HarEntryMetadata -Path $harDestination `
  -EntryName 'package/libs/x86_64/libuc_ohos_napi.so'
$embeddedDeclaration = Get-HarEntryMetadata -Path $harDestination `
  -EntryName 'package/src/main/cpp/types/libuc_ohos_napi/index.d.ts'
$fileNames = @(
  'UniClipboardEngine.har',
  'UniClipboardEngine.har.checksum.txt',
  'index.d.ts',
  'release-manifest.json',
  'dependency-licenses.json',
  'LICENSE',
  'source-commit.txt',
  'uc-ohos-napi.checksum.txt',
  'uc-ohos-napi-x86_64.checksum.txt',
  'version.txt'
)
$files = @($fileNames | ForEach-Object {
  $assetPath = Join-Path $destination $_
  [ordered]@{
    name = $_
    sha256 = Get-Sha256Hex -Path $assetPath
    size = (Get-Item -LiteralPath $assetPath).Length
  }
})
$release = [ordered]@{
  schemaVersion = 1
  version = $version
  packageVersion = $packageVersion
  sourceCommit = $SourceCommit
  releaseUrl = "https://github.com/cwxsss/Engine/commit/$SourceCommit"
  assetBaseUrl = ''
  minimumHarmonyOsApi = 24
  embeddedLibrary = $embeddedArm64
  embeddedLibraries = @($embeddedArm64, $embeddedX86)
  embeddedDeclaration = $embeddedDeclaration
  files = $files
}
Write-Utf8File -Path (Join-Path $destination 'engine-release.json') `
  -Content (($release | ConvertTo-Json -Depth 8) + "`n")

Write-Output "Staged immutable Engine $version at $destination"
