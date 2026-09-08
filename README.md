# Health2BPM

Health2BPM is an iOS and Apple Watch prototype that reads heart rate from Apple Watch, combines it with a selected mood, and suggests Spotify tracks close to the current BPM.

## Features

- SwiftUI native iOS app with a tab-based interface
- watchOS companion app for heart-rate measurement
- HealthKit heart-rate reading on Apple Watch
- WatchConnectivity BPM sync from Apple Watch to iPhone
- Spotify OAuth PKCE login from the iOS app
- Spotify API settings screen for Client ID, Redirect URI, and market
- Track suggestions based on mood and heart-rate BPM

## Requirements

- Xcode with iOS 26 / watchOS 26 SDK support
- iOS 17.0 or later
- watchOS 10.0 or later
- Apple Developer signing team with HealthKit capability enabled
- Spotify Developer app

## Setup

This repository includes both `project.yml` for XcodeGen and a generated `Health2BPM.xcodeproj`.

To regenerate the Xcode project:

```sh
brew install xcodegen
xcodegen generate
open Health2BPM.xcodeproj
```

Or open the existing project directly:

```sh
open Health2BPM.xcodeproj
```

## Spotify Configuration

Create an app in the Spotify Developer Dashboard and register this Redirect URI exactly:

```text
health2bpm://spotify-callback
```

In the iOS app, open the Spotify API settings screen and enter:

- Spotify Client ID
- Redirect URI
- Market, for example `JP`

This app uses OAuth PKCE, so a Spotify Client Secret should not be stored in the mobile app.

## Notes

- Apple Watch requires HealthKit permission to read heart rate.
- Spotify playback control requires an available Spotify playback device or app.
- Suggested tracks are for entertainment and workout support only, not medical use.
- `DerivedData`, user-specific Xcode settings, local environment files, and signing artifacts are intentionally ignored by git.

## Spotify session handling

The iOS app stores its session in Keychain (`WhenUnlockedThisDeviceOnly`), restores it
for the same Client ID and Redirect URI, and refreshes expiring access tokens on demand.
A missing refresh token in a refresh response preserves the previous refresh token.
Concurrent refresh requests share one operation. A 401 triggers at most one refresh/retry;
403 and 429 show actionable messages without automatic retry loops.
Settings include local disconnect; changing Client ID or Redirect URI requires reconnecting.
Raw OAuth responses and tokens are not displayed or logged.

### Authentication validation

Open `Package.swift` in Xcode, select the `Health2BPMAuth` scheme and an iPhone simulator,
and run Product > Test. These isolated tests cover callback validation, session restoration,
client mismatch, refresh-token retention, and error redaction. The app project is unchanged.
The tests require an iOS SDK; `swift test` on Linux/macOS cannot import UIKit.

Also build the app and check on a physical iPhone:
- Login, cancel, deny access, and retry; verify the browser appears over the active window.
- Relaunch after login and fetch without logging in again.
- Expire/revoke the session and verify refresh or a reconnect prompt.
- Disconnect/change credentials while a request is pending; old responses must not restore it.
- Verify playback success (204), no active player (404), forbidden (403), and rate limiting (429).

Recommendations API availability remains dependent on the Spotify app's access. This change
improves authentication and error handling; it does not replace the deprecated recommendation API.
