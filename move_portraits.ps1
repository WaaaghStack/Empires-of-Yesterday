# Moves marine_portrait_*.png files into assets/portraits/
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $projectRoot "assets\portraits"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$moved = 0
Get-ChildItem -Path $projectRoot -Filter "marine_portrait*.png" -File | ForEach-Object {
    $target = Join-Path $dest $_.Name
    Move-Item -Path $_.FullName -Destination $target -Force
    Write-Host "Moved $($_.Name) -> assets/portraits/"
    $moved++
}

Get-ChildItem -Path (Join-Path $projectRoot "assets") -Filter "marine_portrait*.png" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $target = Join-Path $dest $_.Name
    if ($_.DirectoryName -ne $dest) {
        Move-Item -Path $_.FullName -Destination $target -Force
        Write-Host "Moved $($_.Name) -> assets/portraits/"
        $moved++
    }
}

if ($moved -eq 0) {
    Write-Host "No marine_portrait_*.png files found to move."
    Write-Host "Place PNG files in: $dest"
} else {
    Write-Host "Done. Moved $moved file(s)."
}
