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
