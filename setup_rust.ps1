# setup_rust.ps1
# One helper script for the Empires of Yesterday Rust GDExtension.
#
# What it does:
# 1. Checks if Rust (cargo) is installed.
# 2. If not, tells you exactly how to install it.
# 3. If yes, builds the empire_territory crate (debug + release).
# 4. Copies the resulting .dll files into the correct bin/ location.
# 5. Optionally runs the smoke test.
#
# Usage (from repo root in PowerShell):
#   .\setup_rust.ps1
#   .\setup_rust.ps1 -RunSmokeTest
#
# After the very first Rust install, you usually need to close and reopen PowerShell.

param(
    [switch]$RunSmokeTest
)

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot
$CrateDir = Join-Path $RepoRoot "rust\empire_territory"
$BinDir   = Join-Path $CrateDir "bin"

function Write-Info($msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Success($msg){ Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg)   { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)    { Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Host "=== Empires of Yesterday - Rust GDExtension Setup ===" -ForegroundColor Magenta
Write-Host ""

# 1. Check for cargo
$cargo = Get-Command cargo -ErrorAction SilentlyContinue
if (-not $cargo) {
    Write-Err "Rust toolchain (cargo) is NOT installed on this machine."
    Write-Host ""
    Write-Host "Please install it now:" -ForegroundColor White
    Write-Host "  winget install -e --id Rustlang.Rustup" -ForegroundColor Yellow
    Write-Host "  (or go to https://rustup.rs/ and run the installer)"
    Write-Host ""
    Write-Host "After the installer finishes:" -ForegroundColor White
    Write-Host "  1. CLOSE this PowerShell window completely" -ForegroundColor Yellow
    Write-Host "  2. Open a brand new PowerShell window" -ForegroundColor Yellow
    Write-Host "  3. Run this script again:  .\setup_rust.ps1" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Success "Found Rust: $(cargo --version)"

# 2. Build
Write-Info "Building empire_territory (debug)..."
Push-Location $CrateDir
cargo build
Write-Success "Debug build complete."

Write-Info "Building empire_territory (release)..."
cargo build --release
Pop-Location
Write-Success "Release build complete."

# 3. Copy DLLs
Write-Info "Copying DLLs into bin/ folder (matching the .gdextension names)..."

$debugDll   = Join-Path $CrateDir "target\debug\empire_territory.dll"
$releaseDll = Join-Path $CrateDir "target\release\empire_territory.dll"

if (-not (Test-Path $debugDll)) {
    Write-Err "Debug DLL not found at: $debugDll"
    exit 1
}
if (-not (Test-Path $releaseDll)) {
    Write-Err "Release DLL not found at: $releaseDll"
    exit 1
}

# Ensure bin exists
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

Copy-Item $debugDll   -Destination (Join-Path $BinDir "empire_territory.windows.template_debug.x86_64.dll")   -Force
Copy-Item $releaseDll -Destination (Join-Path $BinDir "empire_territory.windows.template_release.x86_64.dll") -Force

Write-Success "DLLs copied to rust\empire_territory\bin\"

Get-ChildItem $BinDir -Filter *.dll | ForEach-Object { Write-Host "  - $($_.Name)" }

Write-Host ""
Write-Success "Rust extension is ready for Godot."

# 4. Optional smoke test
if ($RunSmokeTest) {
    Write-Info "Running smoke test..."
    $godot = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $godot) {
        Write-Warn "Could not find 'godot' in PATH. Please run manually:"
        Write-Host "  godot --headless --path . -s res://rust_smoke_test.gd" -ForegroundColor Yellow
    } else {
        & godot --headless --path $RepoRoot -s res://rust_smoke_test.gd
    }
} else {
    Write-Host ""
    Write-Info "To test immediately, run:"
    Write-Host "  godot --headless --path . -s res://rust_smoke_test.gd" -ForegroundColor Yellow
    Write-Host ""
    Write-Info "Or re-run this script with the flag:"
    Write-Host "  .\setup_rust.ps1 -RunSmokeTest" -ForegroundColor Yellow
}

Write-Host ""
Write-Success "Done. Next step after smoke test passes: we implement the real simulation kernel."