param(
  [string]$ReleaseRoot = (Join-Path $PSScriptRoot '..\third_party\uniclipboard-engine\v1.1.0-rc.6'),
  [string]$StageRoot = (Join-Path $PSScriptRoot 'uniclipboard-native\dist\official-engine')
)

$ErrorActionPreference = 'Stop'
$verifyScript = Join-Path $PSScriptRoot 'verify-engine-release.ps1'
& $verifyScript -ReleaseRoot $ReleaseRoot
if ($LASTEXITCODE -ne 0) {
  throw "Official Engine verification failed with exit code $LASTEXITCODE"
}

$stageRootPath = [System.IO.Path]::GetFullPath($StageRoot)
New-Item -ItemType Directory -Force -Path $stageRootPath | Out-Null
$stagedAssets = @(
  'UniClipboardEngine.har',
  'index.d.ts',
  'release-manifest.json',
  'engine-release.json',
  'dependency-licenses.json',
  'LICENSE'
)
foreach ($assetName in $stagedAssets) {
  Copy-Item -LiteralPath (Join-Path $ReleaseRoot $assetName) -Destination (Join-Path $stageRootPath $assetName) -Force
}

Write-Output "Staged verified official Engine artifacts at: $stageRootPath"
