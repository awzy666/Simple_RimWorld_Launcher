[CmdletBinding()]
param(
    [string]$GameZipUrl = $env:RIMWORLD_GAME_ZIP_URL,
    [string]$SteamcmdZipUrl = $env:RIMWORLD_STEAMCMD_ZIP_URL
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $root
$previousUrl = $env:RIMWORLD_GAME_ZIP_URL
$previousSteamcmdUrl = $env:RIMWORLD_STEAMCMD_ZIP_URL
try {
    $env:RIMWORLD_GAME_ZIP_URL = $GameZipUrl
    $env:RIMWORLD_STEAMCMD_ZIP_URL = $SteamcmdZipUrl
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Flutter release build failed' }
    $bundle = Join-Path $root 'build/windows/x64/runner/Release'
    foreach ($file in 'rimworld_launcher.exe','rimworld_core.dll','flutter_windows.dll','data/app.so','data/icudtl.dat','msvcp140.dll','vcruntime140_1.dll') {
        if (!(Test-Path -LiteralPath (Join-Path $bundle $file))) { throw "Missing release file: $file" }
    }
    Copy-Item -LiteralPath (Join-Path $root 'README.md') -Destination (Join-Path $bundle 'README.md') -Force
    $output = Join-Path $root 'dist'
    [void][IO.Directory]::CreateDirectory($output)
    $zip = Join-Path $output 'RimWorld-Launcher-0.4.4-windows-x64.zip'
    Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip -Force -CompressionLevel Optimal
    Get-FileHash -LiteralPath $zip -Algorithm SHA256 | Format-List
} finally {
    $env:RIMWORLD_GAME_ZIP_URL = $previousUrl
    $env:RIMWORLD_STEAMCMD_ZIP_URL = $previousSteamcmdUrl
    Pop-Location
}

