param(
  [Parameter(Mandatory = $true)]
  [string]$EngineRoot,
  [Parameter(Mandatory = $true)]
  [string]$HarPath
)

$ErrorActionPreference = 'Stop'

$version = 'v1.1.0-rc.6'
$packageVersion = '1.1.0-rc.6'
$sourceCommit = 'f449698b6e96e5d99549c3fdd076dcd8e68118ce'
$destination = Join-Path $PSScriptRoot '..\third_party\uniclipboard-engine\v1.1.0-rc.6'
$destination = [System.IO.Path]::GetFullPath($destination)
$engineRootPath = [System.IO.Path]::GetFullPath($EngineRoot)
$harPathValue = [System.IO.Path]::GetFullPath($HarPath)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

if (Test-Path -LiteralPath $destination) {
  throw "Refusing to overwrite immutable Engine directory: $destination"
}
if ((& git -C $engineRootPath rev-parse HEAD).Trim() -ne $sourceCommit) {
  throw 'Engine checkout does not match the pinned rc.6 source commit'
}
if (-not (Test-Path -LiteralPath $harPathValue -PathType Leaf)) {
  throw "HarmonyOS HAR not found: $harPathValue"
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

New-Item -ItemType Directory -Path $destination | Out-Null

$harDestination = Join-Path $destination 'UniClipboardEngine.har'
$declarationDestination = Join-Path $destination 'index.d.ts'
$licenseDestination = Join-Path $destination 'LICENSE'
Copy-Item -LiteralPath $harPathValue -Destination $harDestination
Copy-Item -LiteralPath (Join-Path $engineRootPath 'bindings\uc-ohos-napi\ohos\index.d.ts') -Destination $declarationDestination
Copy-Item -LiteralPath (Join-Path $engineRootPath 'LICENSE') -Destination $licenseDestination

$harHash = Get-Sha256Hex -Path $harDestination
$rawLibrary = Join-Path $engineRootPath 'target\ohos-rc6\aarch64-unknown-linux-ohos\debug\libuc_ohos_napi.so'
$rawLibraryHash = Get-Sha256Hex -Path $rawLibrary
Write-Utf8File -Path (Join-Path $destination 'UniClipboardEngine.har.checksum.txt') `
  -Content "$harHash  UniClipboardEngine.har`n"
Write-Utf8File -Path (Join-Path $destination 'uc-ohos-napi.checksum.txt') -Content "$rawLibraryHash`n"
Write-Utf8File -Path (Join-Path $destination 'version.txt') -Content "$version`n"
Write-Utf8File -Path (Join-Path $destination 'source-commit.txt') -Content "$sourceCommit`n"

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
    commit = $sourceCommit
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
      status = 'skipped'
      reason = 'Physical-device acceptance pending consumer integration build'
    }
  }
  artifacts = @(
    [ordered]@{ name = 'UniClipboardEngine.har'; platform = 'harmonyos'; architectures = @('arm64-v8a'); sha256 = $harHash; size = (Get-Item $harDestination).Length },
    [ordered]@{ name = 'index.d.ts'; platform = 'harmonyos'; architectures = @(); sha256 = Get-Sha256Hex -Path $declarationDestination; size = (Get-Item $declarationDestination).Length },
    [ordered]@{ name = 'LICENSE'; platform = 'source'; architectures = @(); sha256 = Get-Sha256Hex -Path $licenseDestination; size = (Get-Item $licenseDestination).Length },
    [ordered]@{ name = 'source-commit.txt'; platform = 'source'; architectures = @(); sha256 = Get-Sha256Hex -Path (Join-Path $destination 'source-commit.txt'); size = (Get-Item (Join-Path $destination 'source-commit.txt')).Length },
    [ordered]@{ name = 'version.txt'; platform = 'source'; architectures = @(); sha256 = Get-Sha256Hex -Path (Join-Path $destination 'version.txt'); size = (Get-Item (Join-Path $destination 'version.txt')).Length }
  )
}
$manifestPath = Join-Path $destination 'release-manifest.json'
Write-Utf8File -Path $manifestPath -Content (($manifest | ConvertTo-Json -Depth 10) + "`n")

$embeddedLibrary = Get-HarEntryMetadata -Path $harDestination `
  -EntryName 'package/libs/arm64-v8a/libuc_ohos_napi.so'
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
  sourceCommit = $sourceCommit
  releaseUrl = "https://github.com/cwxsss/Engine/commit/$sourceCommit"
  assetBaseUrl = ''
  minimumHarmonyOsApi = 24
  embeddedLibrary = $embeddedLibrary
  embeddedDeclaration = $embeddedDeclaration
  files = $files
}
Write-Utf8File -Path (Join-Path $destination 'engine-release.json') `
  -Content (($release | ConvertTo-Json -Depth 8) + "`n")

Write-Output "Staged immutable Engine $version at $destination"
