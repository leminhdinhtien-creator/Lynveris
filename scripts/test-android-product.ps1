param(
    [string]$FlutterExecutable = 'flutter',
    [string]$Device = 'emulator-5554',
    [string]$MobileDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'mobile'),
    [string]$LiveFeedFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.verification\live-feed-url.txt'),
    [string]$AndroidSdk = (Join-Path $env:LOCALAPPDATA 'Android\sdk')
)
$ErrorActionPreference = 'Stop'
$liveUrl = (Get-Content -LiteralPath $LiveFeedFile -Raw).Trim()
if (-not $liveUrl.StartsWith('https://')) { throw 'A current HTTPS feed URL is required.' }
$aaptTool = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName 'aapt.exe' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if (-not $aaptTool) { throw 'Android build-tools/aapt.exe is required for package verification.' }
Push-Location -LiteralPath $MobileDirectory
try {
    # Flutter 3.47 integration runner reads an EXISTING APK's identity before rebuilding.
    # Prebuild + verify QA first, so runner cleanup cannot uninstall the user's main app.
    & $FlutterExecutable build apk --debug -t integration_test/product_flow_test.dart --android-project-arg=lynverisQa=true --dart-define="LIVE_FEED_URL=$liveUrl"
    if ($LASTEXITCODE -ne 0) { throw 'QA preflight build failed.' }
    $packageLine = & $aaptTool dump badging 'build\app\outputs\flutter-apk\app-debug.apk' |
        Select-Object -First 1
    if ($packageLine -notmatch "name='vn\.lynveris\.lynveris\.qa'") {
        throw 'APK identity is not isolated QA. Refusing to start integration runner.'
    }
    Write-Output 'Verified isolated QA package before integration runner startup.'
    & $FlutterExecutable test integration_test/product_flow_test.dart -d $Device --dart-define="LIVE_FEED_URL=$liveUrl"
    if ($LASTEXITCODE -ne 0) { throw 'Android product integration failed; inspect output.' }
} finally {
    Pop-Location
}
