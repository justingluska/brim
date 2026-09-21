# How Brim uses Cap's API

Source of truth on the server side: `packages/web-domain/src/Mobile.ts` and
`apps/web/app/api/mobile/[...route]/route.ts` in
[CapSoftware/Cap](https://github.com/CapSoftware/Cap). This is the API the
official Cap iOS app uses; it is undocumented and unversioned, so a server
upgrade can change it. Brim's `CapKit` mirrors the field names one to one.

Base: `https://<server>/api/mobile`. Authenticated calls send
`Authorization: Bearer <api key>`; the key is a 36-character id from the
server's `auth_api_keys` table with `source = mobile`. A user has one such key
per server: minting a new one deletes the previous one.

## Sign-in

| Call | Notes |
|---|---|
| `GET /session/config` | Which browser providers exist (`appleAuthAvailable`, `googleAuthAvailable`, `workosAuthAvailable`). Also Brim's "is this a Cap server" probe: a 404 means the server predates the mobile API. |
| `POST /session/email/request {email}` | Emails a six-digit code (10-minute TTL). |
| `POST /session/email/verify {email, code}` | Returns `{type:"api_key", apiKey, userId}`. Creates the user if the server allows sign-ups for that domain. |
| `GET /session/request?redirectUri=cap://auth[&provider=google\|apple\|workos]` | Browser flow. Redirects through the server's `/login`, then to `cap://auth?api_key=…&user_id=…`. The server only accepts `cap://auth`, so Brim runs this inside `ASWebAuthenticationSession` with callback scheme `cap`, which intercepts the redirect before iOS would route it to any app owning that scheme. |
| `POST /session/revoke` | Sign out. |

## Library

| Call | Notes |
|---|---|
| `GET /bootstrap` | User, organizations, active org, root folders, and `spaces` (organizations and spaces the user can see; `kind` tells them apart). |
| `PATCH /user/active-organization {organizationId}` | Returns a fresh bootstrap. Listing is scoped to the active org. |
| `GET /caps?page&limit&folderId&spaceId` | No `spaceId`: the user's own caps. `spaceId` = an organization id or a space id from bootstrap. Returns `folders`, `caps`, `total`, `hasMore`. |
| `GET /caps/:id` | `cap`, `summary`, `chapters[{title,start}]`, `transcriptionStatus`, `comments[]` (text and emoji), `shareUrl`. Access: owner, shared to the active org, or in a visible space; password-protected caps answer 403 (the mobile API has no password unlock). |
| `GET /caps/:id/thumbnail?v=…` | Authenticated; 302 to a signed storage URL. Brim drops the bearer header on the cross-host redirect (S3-style storage rejects a request carrying both a query signature and an Authorization header). `thumbnailCacheKey` changes when the cap changes. |
| `GET /caps/:id/playback` | `{kind: "mp4"\|"hls", url, transcriptUrl}`. `url` is a signed storage URL valid for one hour; Brim re-fetches after 50 minutes and on failure. If `url` is on the Cap server itself (`/api/playlist?…&videoType=segments-master`) the desktop recording is still finalizing; that route only honours the browser cookie. |
| `GET /caps/:id/download` | Owner only. `{fileName, url}`. |
| `GET /caps/:id/analytics?range=24h\|7d\|30d\|lifetime` | `{available, data}`. |

## Edits

| Call | Notes |
|---|---|
| `PATCH /caps/:id/title {title}` | Returns the updated summary. |
| `PATCH /caps/:id/sharing {public}` | |
| `PATCH /caps/:id/password {password\|null}` | `null` removes it; Brim sends the literal JSON null. |
| `DELETE /caps/:id` | |
| `POST /caps/:id/comments {content, timestamp, parentCommentId?}` | Returns the created comment. |
| `POST /caps/:id/reactions {content, timestamp}` | `content` is the emoji. |
| `DELETE /comments/:id` | |
| `POST /folders {name, color?, spaceId?}` | |

## Not used

- `/api/developer/v1` (the documented `csk_` "Developer API"): it lists videos
  created by a developer app, not a user's library, and it is credit-metered.
- `/api/v1` (the Agent/CLI API): a fuller surface with `cap_cli_` scoped
  tokens; it rejects mobile keys. A future option if the mobile API
  disappears.
- Upload and recording endpoints: Brim is a viewer.
