# Runs Godot 4.7 for this project. Resolution order: $env:GODOT, `godot` on PATH,
# then the editor folder that sits next to the repository.
# Usage: tools\godot.ps1 --headless --path . res://tests/check_scripts.tscn
$sibling = Join-Path $PSScriptRoot '..\..\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$onPath = Get-Command godot -ErrorAction SilentlyContinue

if ($env:GODOT) { $bin = $env:GODOT }
elseif ($onPath) { $bin = $onPath.Source }
elseif (Test-Path $sibling) { $bin = (Resolve-Path $sibling).Path }
else {
	Write-Error "Godot 4.7 not found. Set GODOT to the editor binary or put 'godot' on the PATH."
	exit 127
}

& $bin @args
exit $LASTEXITCODE
