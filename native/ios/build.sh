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
  "$scons_bin" -C "$script_dir" \
    target="$target" \
    arch="$arch" \
    simulator="$simulator" \
    plugin=gamecenter \
    version=4.0 \
    godot_dir="$GODOT_SOURCE_DIR" \
    target_path="$build_dir/"
}

for target in release_debug release; do
  build_slice "$target" arm64 no
  build_slice "$target" arm64 yes
  build_slice "$target" x86_64 yes

  xcrun lipo -create \
    "$build_dir/libgamecenter.arm64-simulator.$target.a" \
    "$build_dir/libgamecenter.x86_64-simulator.$target.a" \
    -output "$build_dir/libgamecenter-simulator.$target.a"

  framework_variant="release"
  if [[ "$target" == "release_debug" ]]; then
    framework_variant="debug"
  fi
  framework_path="$output_dir/gamecenter.$framework_variant.xcframework"
  if [[ -e "$framework_path" ]]; then
    rm -rf "$framework_path"
  fi
  xcodebuild -create-xcframework \
    -library "$build_dir/libgamecenter.arm64-ios.$target.a" \
    -library "$build_dir/libgamecenter-simulator.$target.a" \
    -output "$framework_path"
done

install -m 0644 "$script_dir/gamecenter/gamecenter.gdip" "$output_dir/gamecenter.gdip"
echo "Installed iOS XCFrameworks in ios/plugins/game_services."
