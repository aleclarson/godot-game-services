#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/.." && pwd)"

cd "$repository_root"
./scripts/test.sh
./scripts/test_clean_install.sh

android_variants=(debug release)
for variant in "${android_variants[@]}"; do
  aar="addons/game_services/bin/android/$variant/GodotPlayGameServices-$variant.aar"
  test -s "$aar"
  unzip -tqq "$aar"
done

ios_variants=(debug release)
for variant in "${ios_variants[@]}"; do
  framework="ios/plugins/game_services/gamecenter.$variant.xcframework"
  test -s "$framework/Info.plist"
  plutil -lint "$framework/Info.plist" >/dev/null

  device_library="$(find "$framework/ios-arm64" -maxdepth 1 -type f -name '*.a' -print -quit)"
  simulator_library="$(find "$framework/ios-arm64_x86_64-simulator" -maxdepth 1 -type f -name '*.a' -print -quit)"
  test -n "$device_library"
  test -n "$simulator_library"
  xcrun lipo "$device_library" -verify_arch arm64
  xcrun lipo "$simulator_library" -verify_arch arm64 x86_64
done

test -s ios/plugins/game_services/gamecenter.gdip
echo "PASS: Godot scripts, Android AARs, and iOS XCFrameworks are valid."
