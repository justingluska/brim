# Contributing to Brim

Thanks for taking a look. Brim is small on purpose: a viewer for Cap
recordings that works with any Cap server.

## Ground rules

- **Clean room.** Do not copy code, types or assets from
  [CapSoftware/Cap](https://github.com/CapSoftware/Cap). That repository is
  AGPL-3.0 and Brim is MIT. Reading its API contract to learn the wire format
  is fine; pasting from it is not.
- **No Cap branding.** No Cap logo, no "Cap" in the app name or icon.
- **No tracking.** No analytics, crash reporters or third-party SDKs.
- **No personal data in the repo.** Test fixtures must have identifiers,
  names, titles, hosts and signatures replaced.

## Getting set up

```sh
brew install xcodegen
DEVELOPMENT_TEAM=YOURTEAMID xcodegen generate
open Brim.xcodeproj
```

Run `xcodegen generate` again whenever you add, move or delete a file, or
change `project.yml`. The generated project and `Brim/Info.plist` are
gitignored.

## Where things go

- Networking, models and anything testable without a UI: `Packages/CapKit`.
  Add a test. `swift test` runs on macOS and Linux.
- Screens and view models: `Brim/Views`. Shared state: `Brim/Services`.
- Colors and shared styles: `Brim/Resources/Theme.swift`.
- The deployment target is iOS 17. Check API availability; the compiler only
  catches it when you build for 17.

## Demo mode and screenshots

`Brim/Services/DemoMode.swift` is a fake Cap server that lives inside the app:
a `URLProtocol` that answers the mobile API with invented people, titles,
generated thumbnails and a bundled synthetic video. "Try the demo" on the
sign-in screen uses it, and so does the `-BrimDemo` launch argument, which also
keeps the app away from the Keychain.

`BrimUITests/ScreenshotTests.swift` launches with `-BrimDemo`, walks the main
screens and attaches a PNG of each to the test results. The README images come
from there. If you change a screen, run that test and update
`docs/screenshots/`. Never add a screenshot taken from a real account.

If you add an endpoint to `CapKit`, teach the demo server to answer it too, or
the demo will show an error on that screen.

## Pull requests

- One topic per pull request, with a short description of what changed and
  how you tested it (device or simulator, which server version).
- If you change how Brim talks to the server, update `docs/api.md`.
- If a server upgrade changed a response shape, refresh the scrubbed fixture
  in `Packages/CapKit/Tests/CapKitTests/Fixtures` alongside the model change.

## Reporting bugs

Please include the iOS version, whether the server is cap.so or self-hosted,
the server's Cap version if you know it, and what you saw. Never paste API
keys, signed URLs or share links to private recordings into an issue.
