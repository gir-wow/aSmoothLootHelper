# deploy.ps1 — Copy aSmoothLootHelper addon files into a selected WoW client AddOns folder.
# Run from anywhere. Requires Administrator if WoW is in Program Files.
#
# Usage:  .\scripts\deploy.ps1
#         .\scripts\deploy.ps1 -Destination "D:\Games\WoW\_classic_\Interface\AddOns\aSmoothLootHelper"
#         .\scripts\deploy.ps1 -ClientFlavor classic_era

param(
    [string]$Source      = "C:\git\aSmoothLootHelper",
    [string]$Destination = "",
    [ValidateSet("classic", "anniversary", "classic_era")]
    [string]$ClientFlavor = "classic"
)

if (-not $Destination -or $Destination.Trim() -eq "") {
    $base = "C:\Program Files (x86)\World of Warcraft"
    switch ($ClientFlavor) {
        "classic"      { $branch = "_classic_" }
        "anniversary"  { $branch = "_anniversary_" }
        "classic_era"  { $branch = "_classic_era_" }
        default          { $branch = "_classic_" }
    }
    $Destination = Join-Path $base "$branch\Interface\AddOns\aSmoothLootHelper"
}

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
