# AI vs AI FPS soak — windowed Godot (NOT headless; FPS needs a real window).
# Usage (from repo root or anywhere):
#   powershell -File tools/run_ai_vs_ai_fps_soak.ps1
#   $env:EOY_SOAK_SEC=300; powershell -File tools/run_ai_vs_ai_fps_soak.ps1
# Report: logs/ai_vs_ai_fps_soak_result.txt
# Exit 0 = PASS (mid avg >= 50; late 3-6m avg FPS >= 50 and min >= 40), else 1.

param()

$ErrorActionPreference = "Stop"

$GODOT = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$REPO = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not (Test-Path -LiteralPath $GODOT)) {
    Write-Error "Godot not found at: $GODOT"
    exit 1
}

$env:EOY_AI_VS_AI = "1"
if (-not $env:EOY_SOAK_SEC) {
    $env:EOY_SOAK_SEC = "360"
}

Write-Host "REPO=$REPO"
Write-Host "GODOT=$GODOT"
Write-Host "EOY_AI_VS_AI=$env:EOY_AI_VS_AI"
Write-Host "EOY_SOAK_SEC=$env:EOY_SOAK_SEC"
Write-Host "Launching windowed soak ($env:EOY_SOAK_SEC sec wall)..."

$p = Start-Process -FilePath $GODOT `
    -ArgumentList @("--path", $REPO, "-s", "res://tools/ai_vs_ai_fps_soak.gd") `
    -Wait -PassThru -WorkingDirectory $REPO

$exitCode = $p.ExitCode
Write-Host "EXIT:$exitCode"
exit $exitCode
