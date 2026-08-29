#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
godot_binary="${GODOT_BIN:-godot}"

"$godot_binary" --headless --editor --path "$repo_dir" --quit
"$godot_binary" --headless --path "$repo_dir" --script res://tests/test_runner.gd
