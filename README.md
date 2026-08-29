# Godot Game Services

A normalized Godot 4 API for Apple Game Center and Google Play Games
Services.

> [!WARNING]
> This is a development preview targeting Godot 4.7.2. The scripts, Android
> bridge, clean Android export, and iOS device/simulator links are validated,
> but live service flows still need testing on devices against games configured
> in App Store Connect and Play Console.

## What it provides

- one `GameServices` autoload on iOS, Android, and desktop
- logical achievement and leaderboard IDs mapped to each platform
- request objects that make concurrent asynchronous operations attributable
- portable success and error results with native details preserved
- runtime capability checks for features without true platform parity
- named binary cloud saves with explicit conflict results and resolution
- a stateful mock provider for editor development and automated tests
- bundled Android AARs and iOS XCFrameworks, with their buildable source forks

The API covers authentication, player profiles, achievements, leaderboards,
platform UI, server credentials, and cloud saves. See the
[feasibility research](docs/research.md) for the semantic differences the API
deliberately does not conceal.

## Installation

Copy both of these directories into the same paths in a Godot project:

```text
addons/game_services
ios/plugins/game_services
```

Enable **Game Services** in **Project > Project Settings > Plugins**. This
installs the `GameServices` autoload and registers the bundled Android export
plugin.

The native binaries target Godot 4.7.2 exactly. Rebuild them from `native/` for
another Godot version; native Godot plugins are not assumed to be ABI-compatible
between releases.

Complete the platform-console and export configuration in
[Platform setup](docs/setup.md) before testing on a device.

## Quick start

Copy `game_services_config.example.tres` to
`res://game_services_config.tres`, then replace the platform IDs:

```text
[gd_resource type="Resource" script_class="GameServicesConfig" load_steps=2 format=3]

[ext_resource type="Script" path="res://addons/game_services/game_services_config.gd" id="1"]

[resource]
script = ExtResource("1")
apple_achievement_ids = {"first_win": "com.example.first-win"}
google_achievement_ids = {"first_win": "CgkI..."}
google_achievement_steps = {"first_win": 1}
apple_leaderboard_ids = {"high_score": "com.example.high-score"}
google_leaderboard_ids = {"high_score": "CgkI..."}
```

Use only logical IDs in game code:

```gdscript
var auth := await GameServices.authenticate().wait()
if not auth.ok:
	push_warning(auth.error_message)
	return

var achievement := await GameServices.unlock_achievement("first_win").wait()
var score := await GameServices.submit_score("high_score", 42_000).wait()
```

An immediate validation failure is safe to await because
`GameServicesRequest.wait()` first checks whether the request already
completed.

See the [API contract](docs/api.md) for operations, result shapes, and cloud-save
conflict handling.

## Capability checks

Do not infer support from the operating system:

```gdscript
if GameServices.supports(GameServices.Capability.CLOUD_SAVES):
	var saves := await GameServices.list_saved_games().wait()
```

Unsupported operations return `GameServicesResult.Code.UNSUPPORTED`; missing
native plugins return `UNAVAILABLE`; missing logical ID mappings return
`NOT_CONFIGURED`.

## Development

Open the repository as a Godot project to run the interactive mock-provider
example, or run the automated validation:

```bash
./scripts/test.sh
./scripts/validate_package.sh
```

On macOS, `./scripts/test_exports.sh` performs clean-project Android and iOS
exports, inspects the packaged integrations, and links the generated Xcode
project for both device and simulator. It requires the Android export toolchain
to be configured in Godot with JDK 17, plus Xcode command-line tools.

Rebuild native artifacts with `native/android/build.sh` and
`native/ios/build.sh`. The iOS script requires `GODOT_SOURCE_DIR` to point to an
exact matching Godot source checkout with generated headers.

Architecture and API rationale live in [docs/architecture.md](docs/architecture.md).

## License

[MIT](LICENSE). The native forks and bundled artifacts retain their upstream
MIT notices; see [third-party notices](THIRD_PARTY_NOTICES.md).
