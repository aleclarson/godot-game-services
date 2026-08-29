#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/.." && pwd)"
godot_binary="${GODOT_BIN:-godot}"
fixture_dir="$(mktemp -d /tmp/godot-game-services.XXXXXX)"

cleanup() {
  case "$fixture_dir" in
    /tmp/godot-game-services.*) rm -rf -- "$fixture_dir" ;;
  esac
}
trap cleanup EXIT

cp -R "$repository_root/tests/integration/clean_project/." "$fixture_dir/"
mkdir -p "$fixture_dir/addons" "$fixture_dir/ios/plugins"
cp -R "$repository_root/addons/game_services" "$fixture_dir/addons/"
cp -R "$repository_root/ios/plugins/game_services" "$fixture_dir/ios/plugins/"

"$godot_binary" --headless --editor --path "$fixture_dir"

if ! rg -q '^GameServices="\*(res://addons/game_services/game_services\.gd|uid://[^\"]+)"$' "$fixture_dir/project.godot"; then
  echo "FAIL: enabling the plugin did not install the GameServices autoload" >&2
  exit 1
fi

"$godot_binary" --headless --path "$fixture_dir"

echo "PASS: documented clean installation flow works."
