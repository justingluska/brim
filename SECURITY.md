# Security

Brim stores a per-device API key for each Cap server you sign in to. It is
kept in the iOS Keychain, marked "this device only", and is sent only to the
server it belongs to. It is never attached to requests for storage URLs.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's private
reporting instead: the **Security** tab of this repository, then **Report a
vulnerability**. Include the iOS version, the Brim version from Settings,
whether the server is cap.so or self-hosted, and steps to reproduce.

Never include real API keys, signed URLs or links to private recordings in a
report. Redact them; the shape is enough.

Problems in the Cap server itself belong with the Cap project at
https://github.com/CapSoftware/Cap.
