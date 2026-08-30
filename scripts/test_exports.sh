#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/.." && pwd)"
godot_binary="${GODOT_BIN:-godot}"
fixture_dir="$(mktemp -d /tmp/godot-game-services-export-fixture.XXXXXX)"
output_dir="$(mktemp -d /tmp/godot-game-services-export-output.XXXXXX)"

cleanup() {
  if [[ "${KEEP_TEST_ARTIFACTS:-0}" == "1" ]]; then
    echo "Export fixture: $fixture_dir" >&2
    echo "Export outputs: $output_dir" >&2
    return
  fi
  case "$fixture_dir" in
    /tmp/godot-game-services-export-fixture.*) rm -rf -- "$fixture_dir" ;;
  esac
  case "$output_dir" in
    /tmp/godot-game-services-export-output.*) rm -rf -- "$output_dir" ;;
  esac
}
trap cleanup EXIT

run_logged() {
  local log_path="$1"
  shift
  if ! "$@" >"$log_path" 2>&1; then
    tail -120 "$log_path" >&2
    return 1
  fi
}

cp -R "$repository_root/tests/integration/clean_project/." "$fixture_dir/"
mkdir -p "$fixture_dir/addons" "$fixture_dir/ios/plugins"
cp -R "$repository_root/addons/game_services" "$fixture_dir/addons/"
cp -R "$repository_root/ios/plugins/game_services" "$fixture_dir/ios/plugins/"

run_logged "$output_dir/install.log" \
  "$godot_binary" --headless --editor --path "$fixture_dir"

if ! rg -q '^GameServices="\*(res://addons/game_services/game_services\.gd|uid://[^\"]+)"$' "$fixture_dir/project.godot"; then
  echo "FAIL: enabling the plugin did not persist the GameServices autoload" >&2
  exit 1
fi

android_apk="$output_dir/game-services-debug.apk"
run_logged "$output_dir/android-export.log" \
  "$godot_binary" --headless --editor --path "$fixture_dir" \
  --install-android-build-template --export-debug Android "$android_apk"

test -s "$android_apk"
rg -q '>123456789012</string>' "$fixture_dir/android/build/res/values/game_services.xml"
merged_manifest="$(find "$fixture_dir/android/build/build/intermediates/merged_manifests" -type f -name AndroidManifest.xml -print -quit)"
test -n "$merged_manifest"
rg -q 'com.google.android.gms.games.APP_ID' "$merged_manifest"
rg -q 'org.godotengine.plugin.v2.GodotPlayGameServices' "$merged_manifest"
rg -q 'org.godotengine.plugin.v2.StoreReview' "$merged_manifest"

ios_name="game-services-ios-debug"
ios_project="$output_dir/$ios_name.xcodeproj"
ios_app_dir="$output_dir/$ios_name"
run_logged "$output_dir/ios-export.log" \
  "$godot_binary" --headless --editor --path "$fixture_dir" \
  --export-debug iOS "$output_dir/$ios_name.zip"

test -d "$ios_project"
test -s "$ios_app_dir/dylibs/ios/plugins/game_services/gamecenter.xcframework/Info.plist"
test -s "$ios_app_dir/dylibs/ios/plugins/game_services/storereview.xcframework/Info.plist"
rg -q 'gamecenter\.xcframework' "$ios_project/project.pbxproj"
rg -q 'storereview\.xcframework' "$ios_project/project.pbxproj"
rg -q 'GameKit\.framework' "$ios_project/project.pbxproj"
rg -q 'StoreKit\.framework' "$ios_project/project.pbxproj"
plutil -p "$ios_app_dir/$ios_name.entitlements" | rg -q '"com\.apple\.developer\.game-center" => true'

run_logged "$output_dir/xcode-device.log" \
  xcodebuild -project "$ios_project" -scheme "$ios_name" -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$output_dir/DerivedData-device" \
  CODE_SIGNING_ALLOWED=NO build

godot_sim_library="$output_dir/$ios_name.xcframework/ios-arm64_x86_64-simulator/libgodot.a"
plugin_sim_library="$ios_app_dir/dylibs/ios/plugins/game_services/gamecenter.xcframework/ios-arm64_x86_64-simulator/libgamecenter-simulator.release_debug.a"
store_review_sim_library="$ios_app_dir/dylibs/ios/plugins/game_services/storereview.xcframework/ios-arm64_x86_64-simulator/libstorereview-simulator.release_debug.a"
godot_sim_arches="$(xcrun lipo -archs "$godot_sim_library")"
plugin_sim_arches="$(xcrun lipo -archs "$plugin_sim_library")"
store_review_sim_arches="$(xcrun lipo -archs "$store_review_sim_library")"
simulator_arch=""
if [[ " $godot_sim_arches " == *" arm64 "* && " $plugin_sim_arches " == *" arm64 "* && " $store_review_sim_arches " == *" arm64 "* ]]; then
  simulator_arch="arm64"
elif [[ " $godot_sim_arches " == *" x86_64 "* && " $plugin_sim_arches " == *" x86_64 "* && " $store_review_sim_arches " == *" x86_64 "* ]]; then
  simulator_arch="x86_64"
else
  echo "FAIL: Godot and Game Center have no common simulator architecture" >&2
  exit 1
fi

run_logged "$output_dir/xcode-simulator.log" \
  xcodebuild -project "$ios_project" -scheme "$ios_name" -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$output_dir/DerivedData-simulator" \
  CODE_SIGNING_ALLOWED=NO ARCHS="$simulator_arch" ONLY_ACTIVE_ARCH=YES build

echo "PASS: clean Android and iOS exports include and link the native game-services plugins."
