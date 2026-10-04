param(
  [Parameter(Mandatory = $true)]
  [string]$EngineRoot
)

$ErrorActionPreference = 'Stop'
$engineRootPath = [System.IO.Path]::GetFullPath($EngineRoot)
$releaseRoot = Join-Path $PSScriptRoot '..\third_party\uniclipboard-engine\v1.1.0-rc.22-harmony'
$releaseRoot = [System.IO.Path]::GetFullPath($releaseRoot)
$metadata = Get-Content -Raw -LiteralPath (Join-Path $releaseRoot 'harmony-adaptation.json') | ConvertFrom-Json
$actualCommit = (& git -C $engineRootPath rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $metadata.sourceCommit) {
  throw "Expected Engine rc22 commit $($metadata.sourceCommit), got $actualCommit"
}
$patchPath = Join-Path $releaseRoot $metadata.patchFile
$sha = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sha -ne $metadata.patchSha256) {
  throw 'The rc22 Harmony adapter patch SHA-256 does not match its metadata'
}
& git -C $engineRootPath apply --reverse --check $patchPath 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Output 'The rc22 Harmony N-API adapter is already applied.'
  exit 0
}
& git -C $engineRootPath apply --check $patchPath
if ($LASTEXITCODE -ne 0) { throw 'The rc22 Harmony adapter patch does not apply cleanly' }
& git -C $engineRootPath apply $patchPath
if ($LASTEXITCODE -ne 0) { throw 'Could not apply the rc22 Harmony adapter patch' }
Write-Output "Applied the rc22 Harmony N-API adapter to $actualCommit."