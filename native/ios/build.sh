#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${GODOT_SOURCE_DIR:-}" ]]; then
  echo "Set GODOT_SOURCE_DIR to the exact Godot source revision used by the target project." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../.." && pwd)"
build_dir="$script_dir/build"
output_dir="$repository_root/ios/plugins/game_services"
scons_bin="${SCONS_BIN:-scons}"

required_headers=(
  "core/version_generated.gen.h"
  "core/extension/gdextension_interface.gen.h"
  "core/disabled_classes.gen.h"
)
for header in "${required_headers[@]}"; do
  if [[ ! -f "$GODOT_SOURCE_DIR/$header" ]]; then
    echo "Missing $GODOT_SOURCE_DIR/$header." >&2
    echo "Generate the matching Godot build headers before compiling this bridge." >&2
    exit 1
  fi
done

mkdir -p "$build_dir" "$output_dir"

build_slice() {
  local target="$1"
  local arch="$2"
  local simulator="$3"
  local plugin="$4"
  "$scons_bin" -C "$script_dir" \
    target="$target" \
    arch="$arch" \
    simulator="$simulator" \
    plugin="$plugin" \
    version=4.0 \
    godot_dir="$GODOT_SOURCE_DIR" \
    target_path="$build_dir/"
}

build_plugin() {
  local plugin="$1"
  for target in release_debug release; do
    build_slice "$target" arm64 no "$plugin"
    build_slice "$target" arm64 yes "$plugin"
    build_slice "$target" x86_64 yes "$plugin"

    xcrun lipo -create \
      "$build_dir/lib$plugin.arm64-simulator.$target.a" \
      "$build_dir/lib$plugin.x86_64-simulator.$target.a" \
      -output "$build_dir/lib$plugin-simulator.$target.a"

    framework_variant="release"
    if [[ "$target" == "release_debug" ]]; then
      framework_variant="debug"
    fi
    framework_path="$output_dir/$plugin.$framework_variant.xcframework"
    if [[ -e "$framework_path" ]]; then
      rm -rf "$framework_path"
    fi
    xcodebuild -create-xcframework \
      -library "$build_dir/lib$plugin.arm64-ios.$target.a" \
      -library "$build_dir/lib$plugin-simulator.$target.a" \
      -output "$framework_path"
  done

  install -m 0644 "$script_dir/$plugin/$plugin.gdip" "$output_dir/$plugin.gdip"
}

build_plugin gamecenter
build_plugin storereview

echo "Installed iOS game-services and StoreReview XCFrameworks in ios/plugins/game_services."
