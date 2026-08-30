# Third-party notices

## Godot Play Game Services

The Android bridge under `native/android` and its bundled AARs are derived from
[`godot-sdk-integrations/godot-play-game-services`](https://github.com/godot-sdk-integrations/godot-play-game-services),
release `v3.4.0`. It is used under the MIT license reproduced in
`native/android/LICENSE.upstream`. The source snapshot begins at commit
`e38b618578572b558691c4f476f70f5e142226ce`.

This fork targets Godot 4.7.2 and adds explicit snapshot-conflict resolution.

## Godot iOS Game Center plugin

The iOS bridge under `native/ios/gamecenter` and its bundled XCFrameworks are
derived from the `gamecenter` plugin in
[`godot-sdk-integrations/godot-ios-plugins`](https://github.com/godot-sdk-integrations/godot-ios-plugins).
The retained source headers contain its MIT license notice.
The source snapshot begins at commit
`caafb2c7fbfb5c72a64f163c76449274fa49abaa`.

This fork targets Godot 4.7.2 and iOS 15, updates score submission and Game
Center presentation to the current GameKit APIs, preserves signed 64-bit
leaderboard scores, and adds named saved-game operations and conflict
resolution.

## Google Play In-App Review library

The Android StoreReview bridge resolves
`com.google.android.play:review:2.0.2` from Google's Maven repository. The
library is distributed under the Apache License, Version 2.0. Its license and
notice are supplied by the resolved dependency during the Gradle export; the
project does not vendor or modify its source.
