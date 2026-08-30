# Godot iOS StoreReview plugin

The `StoreReview` singleton provides the small native surface needed by the
normalized addon API:

- `request_in_app_review()` asks StoreKit to request a review from the active
  foreground scene. StoreKit decides whether a prompt is appropriate.
- `open_store_review_page(url)` hands a configured App Store URL to UIKit.

Neither method reports whether a prompt was displayed or whether a review was
submitted. The bridge is built for the exact Godot version used by the addon.
