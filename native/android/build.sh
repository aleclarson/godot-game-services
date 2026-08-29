#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../.." && pwd)"

cd "$script_dir"
./gradlew :plugin:assembleDebug :plugin:assembleRelease

install -d \
  "$repository_root/addons/game_services/bin/android/debug" \
  "$repository_root/addons/game_services/bin/android/release"
install -m 0644 \
  "$script_dir/plugin/build/outputs/aar/GodotPlayGameServices-debug.aar" \
  "$repository_root/addons/game_services/bin/android/debug/GodotPlayGameServices-debug.aar"
install -m 0644 \
  "$script_dir/plugin/build/outputs/aar/GodotPlayGameServices-release.aar" \
  "$repository_root/addons/game_services/bin/android/release/GodotPlayGameServices-release.aar"

echo "Installed Android AARs in addons/game_services/bin/android."
