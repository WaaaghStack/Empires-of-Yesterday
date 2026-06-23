param(
    [Parameter(Mandatory = $true)]
    [int]$RunIndex
)

$GODOT = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$REPO = Split-Path -Parent $MyInvocation.MyCommand.Path
$SCRATCH = $env:GROK_GOAL_SCRATCH
if ([string]::IsNullOrWhiteSpace($SCRATCH)) {
    $SCRATCH = Join-Path $env:TEMP "grok-goal-builder-qa"
}
$env:GROK_GOAL_SCRATCH = $SCRATCH
New-Item -ItemType Directory -Force -Path $SCRATCH | Out-Null
$log = Join-Path $SCRATCH ("qa_builder_run{0}.log" -f $RunIndex)
$outTmp = Join-Path $SCRATCH ("_godot_stdout_run{0}.tmp" -f $RunIndex)
$errTmp = Join-Path $SCRATCH ("_godot_stderr_run{0}.tmp" -f $RunIndex)
Remove-Item $outTmp, $errTmp -ErrorAction SilentlyContinue

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$sw = New-Object System.IO.StreamWriter($log, $false, $utf8NoBom)
$sw.WriteLine("=== QA builder run $RunIndex ===")
$sw.WriteLine("GODOT_EXE=$GODOT")
$sw.WriteLine("REPO=$REPO")
$sw.WriteLine("SCRATCH=$SCRATCH")
$sw.WriteLine("COMMAND=Start-Process $GODOT --headless --path $REPO res://qa_runner.tscn")
$sw.WriteLine("")
$sw.Close()

Push-Location $REPO
$p = Start-Process -FilePath $GODOT `
    -ArgumentList @("--headless", "--path", $REPO, "res://qa_runner.tscn") `
    -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput $outTmp `
    -RedirectStandardError $errTmp
Pop-Location

$sw = New-Object System.IO.StreamWriter($log, $true, $utf8NoBom)
if (Test-Path $outTmp) {
    $sw.Write([System.IO.File]::ReadAllText($outTmp))
}
if (Test-Path $errTmp) {
    $sw.Write([System.IO.File]::ReadAllText($errTmp))
}
$sw.WriteLine("EXIT:$($p.ExitCode)")
$sw.Close()
exit $p.ExitCode