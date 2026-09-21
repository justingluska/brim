# Releasing

Brim is built by Xcode Cloud and distributed through TestFlight. Nothing
about signing lives in the repository; Xcode Cloud manages certificates and
profiles for the team that owns the product.

## How a build happens

1. A push to `main` (or a manual start) triggers the workflow.
2. `ci_scripts/ci_post_clone.sh` installs XcodeGen, generates
   `Brim.xcodeproj` from `project.yml`, and stamps `CFBundleShortVersionString`
   from the newest `v*` tag reachable from the commit (`v0.2.0` → `0.2.0`).
   With no tag it keeps the version in `project.yml`. Xcode Cloud sets the
   build number itself.
3. The workflow runs the unit tests on a simulator and archives for TestFlight.

## Cutting a version

```sh
git tag v0.1.0
git push origin main v0.1.0
```

Never hand-edit version numbers in `project.yml` or `Info.plist`; move the tag.

## Setting up Xcode Cloud for your own fork

1. Create an App Store Connect app record for your bundle identifier (change
   `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`). The signing team is never
   committed: Xcode Cloud passes it through `CI_TEAM_ID`, and locally you run
   `DEVELOPMENT_TEAM=YOURTEAMID xcodegen generate`.
2. `xcodegen generate && open Brim.xcodeproj`, set your team under Signing &
   Capabilities, and build once locally.
3. Xcode → Integrate → Xcode Cloud → Get Started, pick the Brim product, connect
   the repository, accept the default workflow. Everything after that can be
   changed in App Store Connect or through its API.

## App Store

Brim is a third-party client. Before submitting a build for public
distribution, get written permission from Cap Software, Inc. to describe the
app as "for Cap" (Apple's guideline 5.2.2). TestFlight and building from
source need no such permission.
