# Godot Game Services

An exploration of a normalized Godot 4 interface for Apple Game Center and
Google Play Games Services.

## Status

Feasibility research. There is no stable API or distributable plugin yet.

## Direction

The plugin should expose the shared capabilities of both services through one
GDScript-facing API while keeping platform-specific code behind native iOS and
Android adapters. Features that cannot be normalized cleanly should remain
explicit rather than being hidden behind misleading parity.

The initial common surface to investigate is:

- authentication and player identity
- achievements
- leaderboards and score submission
- platform UI overlays
- saved-game support and conflict handling
- lifecycle, error, and offline behavior

A possible shape for the public API is:

```gdscript
GameServices.sign_in()
GameServices.unlock_achievement("first_win")
GameServices.submit_score("high_score", 42_000)
GameServices.show_leaderboards()
```

Game-specific identifiers would be mapped to the corresponding Game Center and
Play Games identifiers in configuration rather than branching throughout game
code.

## Questions to answer

1. Which capabilities have genuinely compatible semantics on both platforms?
2. Which Godot native-plugin and export mechanisms provide the cleanest install
   and release workflow?
3. How should authentication, cancellation, offline operation, and app lifecycle
   events be represented consistently?
4. Where are platform-specific escape hatches necessary?
5. Can most of the GDScript-facing behavior be tested without live platform
   services?

## Likely architecture

```text
Game code
    -> normalized GDScript API
        -> Apple Game Center adapter (iOS)
        -> Google Play Games Services adapter (Android)
        -> mock adapter (editor and tests)
```

The next step is a capability matrix based on the current native SDKs and the
state of existing Godot integrations.
