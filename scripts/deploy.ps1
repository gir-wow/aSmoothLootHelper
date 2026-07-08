# deploy.ps1 — Copy aSmoothLootHelper addon files into the WoW MoP Classic AddOns folder.
# Run from anywhere. Requires Administrator if WoW is in Program Files.
#
# Usage:  .\scripts\deploy.ps1
#         .\scripts\deploy.ps1 -Destination "D:\Games\WoW\_classic_\Interface\AddOns\aSmoothLootHelper"

param(
    [string]$Source      = "C:\git\aSmoothLootHelper",
    [string]$Destination = "C:\Program Files (x86)\World of Warcraft\_classic_\Interface\AddOns\aSmoothLootHelper"
)

# Only these directories / files belong in the addon
$addonDirs  = @("Core", "Providers", "UI")
$addonFiles = @("aSmoothLootHelper.toc", "aSmoothLootHelper.lua")

# Clean previous deploy
if (Test-Path $Destination) {
    Remove-Item $Destination -Recurse -Force
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

# Copy top-level addon files
foreach ($file in $addonFiles) {
    $src = Join-Path $Source $file
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $Destination $file) -Force
    } else {
        Write-Warning "Missing file: $src"
    }
}

# Copy addon sub-directories
foreach ($dir in $addonDirs) {
    $srcDir = Join-Path $Source $dir
    if (Test-Path $srcDir) {
        Copy-Item $srcDir (Join-Path $Destination $dir) -Recurse -Force
    }
}

Write-Host "Deployed aSmoothLootHelper to $Destination" -ForegroundColor Green
