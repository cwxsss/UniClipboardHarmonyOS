[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$checks = @(
    @{
        Path = 'products/default/src/main/module.json5'
        Pattern = '"backgroundModes"\s*:\s*\[\s*"dataTransfer"\s*\]'
    },
    @{
        Path = 'common/src/main/ets/service/BackgroundSyncService.ets'
        Pattern = "taskModes:\s*string\[\]\s*=\s*\['dataTransfer'\]"
    }
)

$errors = [System.Collections.Generic.List[string]]::new()
foreach ($check in $checks) {
    $path = Join-Path $repoRoot $check.Path
    $content = Get-Content -LiteralPath $path -Raw
    if ($content -notmatch $check.Pattern) {
        $errors.Add($check.Path)
    }
    if ($content.Contains("'multiDeviceConnection'") -or
        $content.Contains('"multiDeviceConnection"')) {
        $errors.Add("$($check.Path) (legacy multiDeviceConnection mode)")
    }
}

if ($errors.Count -gt 0) {
    throw @"
HarmonyOS background sync mode regression detected:
$($errors -join [Environment]::NewLine)

UniClipboard transfers clipboard data through the iroh/QUIC data channel. It must declare and
request dataTransfer. multiDeviceConnection appears to start successfully but HarmonyOS suspends
the process after about 65 seconds, which breaks desktop-to-phone clipboard delivery in background.
"@
}

Write-Host 'HarmonyOS background sync mode verification passed (dataTransfer).'
