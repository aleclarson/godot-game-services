#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/.." && pwd)"

cd "$repository_root"
./scripts/test.sh
./scripts/test_clean_install.sh

android_variants=(debug release)
android_plugins=(GodotPlayGameServices StoreReview)
for variant in "${android_variants[@]}"; do
  for plugin in "${android_plugins[@]}"; do
    aar="addons/game_services/bin/android/$variant/$plugin-$variant.aar"
    test -s "$aar"
    unzip -tqq "$aar"
  done
done

ios_variants=(debug release)
ios_plugins=(gamecenter storereview)
for variant in "${ios_variants[@]}"; do
  for plugin in "${ios_plugins[@]}"; do
    framework="ios/plugins/game_services/$plugin.$variant.xcframework"
    test -s "$framework/Info.plist"
    plutil -lint "$framework/Info.plist" >/dev/null

    device_library="$(find "$framework/ios-arm64" -maxdepth 1 -type f -name '*.a' -print -quit)"
    simulator_library="$(find "$framework/ios-arm64_x86_64-simulator" -maxdepth 1 -type f -name '*.a' -print -quit)"
    test -n "$device_library"
    test -n "$simulator_library"
    xcrun lipo "$device_library" -verify_arch arm64
    xcrun lipo "$simulator_library" -verify_arch arm64 x86_64
  done
done

test -s ios/plugins/game_services/gamecenter.gdip
test -s ios/plugins/game_services/storereview.gdip
rg -q 'StoreKit\.framework' ios/plugins/game_services/storereview.gdip
echo "PASS: Godot scripts, Android AARs, and iOS XCFrameworks are valid."
