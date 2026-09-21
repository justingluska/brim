# Brim privacy

Brim is a client for Cap servers. It has no backend of its own.

- **What leaves the phone:** requests to the Cap server you signed in to
  (cap.so or your self-hosted address) and media fetches from the storage
  endpoint that server returns. Nothing else. There is no analytics, crash
  reporting, advertising, or telemetry in the app.
- **What is stored on the phone:** your accounts (server address, email,
  display name and the per-device API key) in the iOS Keychain, marked
  "after first unlock, this device only" so they never sync to iCloud
  Keychain. Thumbnails are cached in memory only. Downloaded videos go to the
  app's temporary directory until you share or the system clears them.
- **Signing out** revokes the key on the server and deletes it from the
  Keychain.
- **Comments, reactions, renames, visibility changes and deletions** are
  sent to your Cap server exactly as if you had done them on the web.

Questions: open an issue on the repository.
