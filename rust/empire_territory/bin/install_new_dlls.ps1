# Install staged empire_territory DLLs after Godot is fully closed.
# Usage (from repo root):  powershell -File rust\empire_territory\bin\install_new_dlls.ps1

$ErrorActionPreference = "Stop"
$BinDir = $PSScriptRoot

$pairs = @(
    @{ New = "empire_territory.windows.template_debug.x86_64.dll.new"; Dest = "empire_territory.windows.template_debug.x86_64.dll" },
    @{ New = "empire_territory.windows.template_release.x86_64.dll.new"; Dest = "empire_territory.windows.template_release.x86_64.dll" }
)

foreach ($p in $pairs) {
    $src = Join-Path $BinDir $p.New
    $dst = Join-Path $BinDir $p.Dest
    if (-not (Test-Path $src)) {
        # Fall back to cargo local target if .new was already consumed
        $crate = Split-Path $BinDir -Parent
        $which = if ($p.Dest -match "debug") { "debug" } else { "release" }
        $src = Join-Path $crate "target\$which\empire_territory.dll"
    }
    if (-not (Test-Path $src)) {
        Write-Host "Missing source for $($p.Dest)" -ForegroundColor Red
        exit 1
    }
    try {
        Copy-Item $src $dst -Force
        Write-Host "OK  $($p.Dest)  $((Get-Item $dst).Length) bytes  $((Get-Item $dst).LastWriteTime)" -ForegroundColor Green
    } catch {
        Write-Host "LOCKED  $($p.Dest) — fully quit Godot, then re-run this script." -ForegroundColor Yellow
        Write-Host "  $_"
        exit 1
    }
}

Write-Host "Done. Restart Godot." -ForegroundColor Cyan
