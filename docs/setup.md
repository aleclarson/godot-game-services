# Platform setup

The addon supplies the Godot-facing API and native bridge binaries. Each game
still owns its platform records, credentials, signing setup, and identifiers.

## Android

1. Create and configure the game in Google Play Console. Link Android OAuth
   credentials whose package name and SHA-1 certificate fingerprints exactly
   match the debug and release builds you will test.
2. Create achievements and leaderboards, then copy their IDs into
   `game_services_config.tres`.
3. Set `google_play_package_name` in `game_services_config.tres`. You may set
   `google_play_store_review_url` when the game needs a custom destination;
   otherwise the package name derives the normal Play Store page URL.
4. If cloud saves are used, enable **Saved Games** in the Play Games Services
   project properties.
5. In Godot, install the Android Gradle build template from the **Project**
   menu and enable the Gradle build in the Android export preset.
6. Set **Game Services > Google Game ID** in the Android export preset to the
   numeric project ID shown in Play Console. This is the application ID used by
   the Play Games SDK, not an OAuth client ID.
7. Add test accounts in Play Console and test an APK signed with a linked
   certificate before publishing the Play Games Services configuration.

The editor export plugin adds the bundled AAR, Gson `2.11.0`, Play Games
Services v2 `22.0.0`, Google Play In-App Review `2.0.2`, the manifest metadata,
and the Android string resource. Store review requests are independent of Play
Games authentication. It requires a Gradle export because the native SDK
dependencies must be resolved during the Android build.

Google's official setup guide explains the package-name, certificate, OAuth,
and tester requirements:
[Set up Play Games Services](https://developer.android.com/games/pgs/console/setup).

## iOS

1. Enable Game Center for the app identifier and configure the game's
   achievements and leaderboards in App Store Connect.
2. Add an iOS export preset in Godot. Enable **Entitlements > Game Center** and
   enable the bundled **GameCenter** and **StoreReview** plugins in the preset.
3. Set `apple_app_store_id` in `game_services_config.tres`. You may set
   `apple_store_review_url` when the game needs a custom destination; otherwise
   the App Store ID derives the standard write-a-review URL.
4. Copy the App Store Connect identifiers into `game_services_config.tres`.
5. Export from macOS with Xcode and test using a sandbox Game Center account.

The StoreReview plugin calls StoreKit using the active foreground scene. Apple
controls eligibility and may suppress the prompt, so a completed request does
not prove that UI appeared or that a review was submitted. Use
`open_store_review_page()` for an explicit, game-controlled fallback.

Cloud saves additionally require iCloud for the app identifier, an iCloud
container, and the iCloud Documents service. Configure those capabilities in
the Apple developer portal and the exported Xcode target. The player's device
must be signed in to iCloud with iCloud Drive enabled. This account/container
configuration cannot be inferred or created by the addon.

Apple's saved-game guide documents the iCloud account, iCloud Drive, container,
and iCloud Documents requirements:
[Saving the player's game data to an iCloud account](https://developer.apple.com/documentation/gamekit/saving-the-player-s-game-data-to-an-icloud-account).

## Godot compatibility

The checked-in AARs and XCFrameworks were compiled against Godot 4.7.2 stable.
The GDScript layer may work on adjacent Godot 4 releases, but the native
artifacts must be rebuilt against the exact engine version used by the game.

For Android, use JDK 17 and an Android SDK containing API 35, then run:

```bash
ANDROID_HOME=/path/to/android-sdk JAVA_HOME=/path/to/jdk-17 \
  ./native/android/build.sh
```

For iOS, first generate the headers in the matching Godot source checkout, then
run:

```bash
GODOT_SOURCE_DIR=/path/to/godot SCONS_BIN=/path/to/scons \
  ./native/ios/build.sh
```
