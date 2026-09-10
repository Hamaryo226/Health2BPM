# Welcome onboarding

Three native SwiftUI pages based on the supplied blue/white reference. Swipe or use
the bottom button/page dots. Completion stores `hasCompletedWelcome` in UserDefaults;
subsequent launches show the existing mood selection. Existing installations see the
introduction once after upgrading. Spotify callbacks remain on the WindowGroup root.
Settings → 使い方を見る presents the introduction again without resetting app state.

The introductory BPM and cards are illustrative, not measurements or playable tracks.
The final copy avoids promising a health benefit. The central card uses sea artwork;
the two side cards use native gradients and symbols instead of the reference photos.
Headings/body/buttons are native text. Content scrolls when height or text size requires
it; bottom controls remain reachable. Page dots have 44-point targets, decorative art
is hidden from VoiceOver, and explicit page animations respect Reduce Motion.

## Validation

Checked locally: `git diff --check`, asset manifest/file consistency and Xcode target
references. This Linux environment has no Swift compiler, Xcode or iOS Simulator.
No native build, runtime or screenshot verification has been performed.

Before merging, on macOS:

1. Build the Health2BPM scheme for an iOS Simulator in Xcode (iOS 17 or later).
2. Fresh installation: confirm all three pages, swiping in both directions, dots,
   button labels, and final transition to the existing mood tab.
3. Relaunch after completing: confirm the introduction is not shown.
4. Settings → 使い方を見る: complete the introduction and confirm settings return.
5. Check a small iPhone, a large iPhone, iPad, landscape, largest accessibility text
   size, VoiceOver and Reduce Motion. Scroll to read all copy in constrained layouts.
6. Check Spotify callback handling and verify introduction/replay starts no new
   HealthKit or Spotify authorization flow.

The checked-in project registers the new source and catalog. `project.yml` already
includes the entire iOS directory. The iOS build configurations' stale AppIcon catalog
name was removed because the repository contains no AppIcon; adding this art catalog
would otherwise cause asset compilation to look for an absent app icon.

## Artwork

Generated with the built-in image generation tool using the user's mockup as a style
reference. Project assets:

- `iOS/WelcomeAssets.xcassets/WelcomeHeart.imageset/WelcomeHeart.png`
- `iOS/WelcomeAssets.xcassets/WelcomeRunner.imageset/WelcomeRunner.png`
- `iOS/WelcomeAssets.xcassets/WelcomeSea.imageset/WelcomeSea.png`

Prompts:

**Heart:** Create a square production hero artwork for an iOS app matching the FIRST
panel of the reference: a single large glossy sculptural blue heart centered slightly
below middle, icy blue white softly blurred studio background, soft grounded shadow.
White glowing ECG line across heart. Keep upper quarter empty for native app title.
No text, no phone, no frame, no UI, no letters. Premium minimalist photorealistic 3D.

**Runner:** Create square photorealistic production hero artwork matching SECOND panel
of reference: rear three quarter view of young adult male runner in dark navy t shirt,
body on left half, head near upper left, running beside water in morning. Pale blue sky
and distant softly blurred city waterfront. Right upper half clear sky for native BPM
label. No text, no numbers, no ECG line, no phone, no UI. Cool blue neutral palette.

**Sea:** Create square photorealistic artwork for a music mood card matching sea image
in THIRD panel of reference: tranquil blue ocean with pastel sunrise at horizon, subtle
clouds, silver blue water foreground. No phone, no frame, no UI, no text or numbers.
Premium photographic detail.
