param(
  [string]$NativeSdk = $env:DEVECO_SDK_HOME
)

$ErrorActionPreference = 'Stop'
$nativeRoot = Join-Path $PSScriptRoot 'uniclipboard-native'
$distRoot = Join-Path $nativeRoot 'dist'
$packageLibs = Join-Path $nativeRoot 'package\libs'
$effectiveNativeSdk = $NativeSdk

if ([string]::IsNullOrWhiteSpace($NativeSdk)) {
  throw 'HarmonyOS SDK path is required. Set DEVECO_SDK_HOME or pass -NativeSdk.'
}

if (-not (Test-Path -LiteralPath (Join-Path $NativeSdk 'native'))) {
  throw "HarmonyOS Native SDK not found under: $NativeSdk"
}

if ($NativeSdk.Contains(' ')) {
  $sdkAlias = Join-Path $PSScriptRoot '.ohos-sdk'
  $sdkRoot = Split-Path -Parent $NativeSdk
  if (-not (Test-Path -LiteralPath $sdkAlias)) {
    New-Item -ItemType Junction -Path $sdkAlias -Target $sdkRoot | Out-Null
  }
  $effectiveNativeSdk = Join-Path $sdkAlias (Split-Path -Leaf $NativeSdk)
}

$env:OHOS_NDK_HOME = $effectiveNativeSdk
Push-Location $nativeRoot
try {
  ohrs build --release --arch aarch
  if ($LASTEXITCODE -ne 0) {
    throw "ohrs build failed with exit code $LASTEXITCODE"
  }
} finally {
  Pop-Location
}

$typeSource = Join-Path $distRoot 'index.d.ts'
$librarySource = Join-Path $distRoot 'arm64-v8a\libuniclipboard_native.so'
if (-not (Test-Path -LiteralPath $typeSource) -or -not (Test-Path -LiteralPath $librarySource)) {
  throw 'ohos-rs did not produce the expected arm64 artifacts'
}

New-Item -ItemType Directory -Path (Join-Path $packageLibs 'arm64-v8a') -Force | Out-Null
Copy-Item -LiteralPath $typeSource -Destination (Join-Path $packageLibs 'index.d.ts') -Force
Copy-Item -LiteralPath $librarySource -Destination (Join-Path $packageLibs 'arm64-v8a\libuniclipboard_native.so') -Force

Write-Output 'Updated uniclipboard_native arm64 HAR artifacts.'
