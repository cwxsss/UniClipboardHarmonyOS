param(
  [Parameter(Mandatory = $true)]
  [string]$UnsignedHap,
  [Parameter(Mandatory = $true)]
  [string]$SignedHap,
  [string]$SdkRoot = '',
  [string]$BundleName = 'com.sss.uniclipboard',
  [string]$SigningDirectory = '',
  [string]$Password = '',
  [string[]]$AllowedAcls = @('ohos.permission.READ_PASTEBOARD')
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SdkRoot)) {
  $SdkRoot = if (-not [string]::IsNullOrWhiteSpace($env:DEVECO_SDK_HOME)) {
    $env:DEVECO_SDK_HOME
  } else {
    throw 'SdkRoot is required when DEVECO_SDK_HOME is not set'
  }
}
if ([string]::IsNullOrWhiteSpace($Password)) {
  $Password = if (-not [string]::IsNullOrWhiteSpace($env:OHOS_TEST_KEYSTORE_PASSWORD)) {
    $env:OHOS_TEST_KEYSTORE_PASSWORD
  } else {
    '123456'
  }
}

$sdkRootPath = [System.IO.Path]::GetFullPath($SdkRoot)
$unsignedHapPath = [System.IO.Path]::GetFullPath($UnsignedHap)
$signedHapPath = [System.IO.Path]::GetFullPath($SignedHap)
$devecoRoot = Split-Path -Parent $sdkRootPath
$toolchainsRoot = Join-Path $sdkRootPath 'default\openharmony\toolchains'
$java = Join-Path $devecoRoot 'jbr\bin\java.exe'
$keytool = Join-Path $devecoRoot 'jbr\bin\keytool.exe'
$signTool = Join-Path $toolchainsRoot 'lib\hap-sign-tool.jar'
$keystore = Join-Path $toolchainsRoot 'lib\OpenHarmony.p12'
$profileTemplate = Join-Path $toolchainsRoot 'lib\UnsgnedReleasedProfileTemplate.json'
$profileCertificate = Join-Path $toolchainsRoot 'lib\OpenHarmonyProfileRelease.pem'

foreach ($path in @($java, $keytool, $signTool, $keystore, $profileTemplate, $profileCertificate, $unsignedHapPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Required signing input is unavailable: $path"
  }
}

$signingRoot = if ([string]::IsNullOrWhiteSpace($SigningDirectory)) {
  Join-Path (Split-Path -Parent $signedHapPath) 'signing'
} else {
  [System.IO.Path]::GetFullPath($SigningDirectory)
}
New-Item -ItemType Directory -Path $signingRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $signedHapPath) -Force | Out-Null

$unsignedProfile = Join-Path $signingRoot 'profile.json'
$signedProfile = Join-Path $signingRoot 'profile.p7b'
$appCertificate = Join-Path $signingRoot 'application.cer'
$verifiedCertificateChain = Join-Path $signingRoot 'verified-cert-chain.cer'
$verifiedProfile = Join-Path $signingRoot 'verified-profile.p7b'

$profile = Get-Content -Raw -LiteralPath $profileTemplate | ConvertFrom-Json
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$profile.validity.'not-before' = $now
$profile.validity.'not-after' = $now + 31536000
$profile.'bundle-info'.'bundle-name' = $BundleName
$profile.acls.'allowed-acls' = @($AllowedAcls)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
  $unsignedProfile,
  ($profile | ConvertTo-Json -Depth 20) + [Environment]::NewLine,
  $utf8NoBom)

if (Test-Path -LiteralPath $appCertificate) {
  Remove-Item -LiteralPath $appCertificate -Force
}
foreach ($alias in @('openharmony application root ca', 'openharmony application ca')) {
  & $keytool `
    -exportcert `
    -rfc `
    -alias $alias `
    -keystore $keystore `
    -storetype PKCS12 `
    -storepass $Password `
    | Out-File -LiteralPath $appCertificate -Encoding ascii -Append
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to export application certificate for alias: $alias"
  }
}
[System.IO.File]::AppendAllText(
  $appCertificate,
  [Environment]::NewLine + $profile.'bundle-info'.'distribution-certificate',
  [System.Text.ASCIIEncoding]::new())

& $java -jar $signTool sign-profile `
  -mode localSign `
  -keyAlias 'openharmony application profile release' `
  -keyPwd $Password `
  -profileCertFile $profileCertificate `
  -inFile $unsignedProfile `
  -signAlg SHA256withECDSA `
  -keystoreFile $keystore `
  -keystorePwd $Password `
  -outFile $signedProfile
if ($LASTEXITCODE -ne 0) {
  throw "sign-profile failed with exit code $LASTEXITCODE"
}

& $java -jar $signTool sign-app `
  -mode localSign `
  -keyAlias 'openharmony application release' `
  -keyPwd $Password `
  -appCertFile $appCertificate `
  -profileFile $signedProfile `
  -profileSigned 1 `
  -inFile $unsignedHapPath `
  -signAlg SHA256withECDSA `
  -keystoreFile $keystore `
  -keystorePwd $Password `
  -outFile $signedHapPath `
  -compatibleVersion 24 `
  -signCode 1
if ($LASTEXITCODE -ne 0) {
  throw "sign-app failed with exit code $LASTEXITCODE"
}

& $java -jar $signTool verify-app `
  -inFile $signedHapPath `
  -outCertChain $verifiedCertificateChain `
  -outProfile $verifiedProfile
if ($LASTEXITCODE -ne 0) {
  throw "verify-app failed with exit code $LASTEXITCODE"
}

$hash = (Get-FileHash -LiteralPath $signedHapPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "Signed and verified HAP: $signedHapPath"
Write-Output "SHA-256: $hash"
