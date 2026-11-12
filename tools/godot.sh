#!/usr/bin/env sh
# Runs Godot 4.7 for this project. Resolution order: $GODOT, `godot` on PATH,
# then the editor folder that sits next to the repository.
# Usage: tools/godot.sh --headless --path . res://tests/check_scripts.tscn
set -e
here="$(cd "$(dirname "$0")" && pwd)"
sibling="$here/../../Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

if [ -n "$GODOT" ]; then
	exec "$GODOT" "$@"
elif command -v godot >/dev/null 2>&1; then
	exec godot "$@"
elif [ -x "$sibling" ]; then
	exec "$sibling" "$@"
fi

echo "Godot 4.7 not found. Set GODOT to the editor binary or put 'godot' on the PATH." >&2
exit 127
