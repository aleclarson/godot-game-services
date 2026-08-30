# Godot Game Services

A normalized Godot 4 API for Apple Game Center and Google Play Games
Services.

> [!WARNING]
> This is a development preview targeting Godot 4.7.2. The scripts, Android
> bridge, clean Android export, and iOS device/simulator links are validated,
> but live service flows still need testing on devices against games configured
> in App Store Connect and Play Console.

## What it provides

This addon is for a Godot game shipping on both iOS and Android that should not
need platform branches throughout its gameplay code.

- Call the same methods for authentication, achievements, leaderboards,
  platform UI, in-app reviews, server credentials, and cloud saves on either
  platform.
- Keep Apple and Google achievement and leaderboard IDs in one configuration
  resource. Game code uses stable, game-owned names such as `first_win`.
- Develop in the editor without a store account or native SDK. The mock provider
  keeps authentication, achievements, scores, saved games, and review fallback
  URLs in memory.
- Match every asynchronous result to the request that started it, including
  concurrent saves or score submissions. Results share portable error codes and
  retain native details for diagnostics.
- Export with the native bridges included. The addon registers its Android AARs
  and dependencies with Gradle; Godot's iOS exporter discovers the bundled
  Game Center and StoreReview XCFrameworks.
- Detect support at runtime instead of assuming similarly named platform
  features behave the same. Unsupported operations fail explicitly.
- Save Godot values rather than manually encoding byte arrays. Typed cloud saves
  carry schema versions, revision ancestry, portable metadata, migrations, and
  explicit conflict candidates. Fixed slots can keep their own defaults,
  validators, and conflict policy.

The addon normalizes client code; it does not merge the two platform backends.
Game Center and Play Games keep separate players, achievements, leaderboards,
and saved games. Cross-platform accounts or progression require your own
backend. The game also remains responsible for App Store Connect, Play Console,
signing, entitlements, and test accounts. See the
[platform setup](docs/setup.md) and [feasibility research](docs/research.md)
before committing to the integration.

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
apple_app_store_id = "123456789012"
google_play_package_name = "com.example.game"
```

Use only logical IDs in game code:

```gdscript
var auth := await GameServices.authenticate().wait()
if not auth.ok:
	push_warning(auth.error_message)
	return

var achievement := await GameServices.unlock_achievement("first_win").wait()
var score := await GameServices.submit_score("high_score", 42_000).wait()

# This is an explicit fallback decision; the addon never redirects automatically.
var review := await GameServices.request_in_app_review().wait()
if not review.ok:
	var store_page := await GameServices.open_store_review_page().wait()
```

`request_in_app_review()` hands the request to StoreKit or Google Play In-App
Review. A successful result means the native flow accepted the request; it does
not mean a prompt was shown or a review was submitted. Use
`open_store_review_page()` only for an explicit user action or fallback. The
Apple and Google IDs above derive their store URLs; set the corresponding
`*_store_review_url` fields when a game needs an explicit URL. Review requests
do not require Game Center or Play Games authentication.

An immediate validation failure is safe to await because
`GameServicesRequest.wait()` first checks whether the request already
completed.

For a fixed save slot, use a configured handle. It keeps the slot name and its
schema settings out of gameplay code:

```gdscript
var campaign := GameServices.cloud_saves.slot("campaign", {
	"level": 1,
	"coins": 0,
})
campaign.schema_version = 2
campaign.add_migration(1, _migrate_save_v1)

var loaded := await campaign.load_or_create().wait()
if not loaded.ok:
	push_warning(loaded.error_message)
	return
var document: CloudSaveDocument = loaded.data

document.value.coins += 10
var written := await campaign.save(document).wait()
if written.ok:
	document = written.data
```

Use `GameServices.cloud_saves` directly when slot names are dynamic. Its
`validate()` and `encoded_size()` methods can preflight a document without
writing it.

For a simple read-modify-write, `campaign.update(mutator)` combines those steps;
the mutator runs once and a concurrent conflict is still returned for the game
to resolve.

Conflict resolution is manual by default. `CloudSaveConflict` exposes decoded
candidates and helpers for choosing the newest or highest-progress copy;
automatic policies require explicit opt-in.

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

Review support is independent of the provider capability mask:

```gdscript
if GameServices.supports_store_review():
	var review := await GameServices.request_in_app_review().wait()
```

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
