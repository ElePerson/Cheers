# iOS App Store Submission Packet

This packet is the release owner’s source of truth for the official Cheers iOS
app. Complete the owner-only fields immediately before submission; do not put
review credentials, passwords, tokens, or private server addresses in Git.

**MVP positioning for first review:** chat + approvals + bots. Composer file
upload is not in the iOS binary yet — say so in Review Notes (template below).
Do not claim Photo Library / camera access that the binary does not request.

## Version identity

| Source | Value | Rule |
| --- | --- | --- |
| Xcode `MARKETING_VERSION` | `1.0.0` | User-facing App Store version |
| Xcode `CURRENT_PROJECT_VERSION` | `1` | Build number; bump on every upload |
| `Sources/Info.plist` | `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` | Must stay substituted — never hard-code a divergent string |

Before Archive, confirm Organizer shows **Version 1.0.0 (1)** (or the bumped
build). A mismatch between `Info.plist` and the project used to ship `0.1.0`
vs `1.0.0` and will confuse ASC / TestFlight.

## Public URLs

| App Store Connect field | Production value | Verification |
| --- | --- | --- |
| Privacy Policy URL | `https://www.tocheers.com/privacy.html` | Opens without sign-in, including on mobile Safari |
| Support URL | `https://www.tocheers.com/support.html` | Opens without sign-in; `tocheers@icloud.com` is monitored |
| Remote-operation policy (linked from product / review notes) | `https://www.tocheers.com/remote-operations.html` | Opens without sign-in |
| Privacy contact | `tocheers@icloud.com` | Mailbox is monitored |

The iOS login and Settings screens link to the privacy and support URLs. Do not
submit until the deployed domain serves these exact paths over HTTPS and the
mailbox is live. After editing `website/privacy*.html`, **redeploy the site**
before Archive so ASC and reviewers see the mic / LiveKit language.

### URL check log (release owner)

| Date | Result | Notes |
| --- | --- | --- |
| 2026-07-28 | **Pass** (browser UA) | `privacy.html`, `support.html`, `remote-operations.html`, `privacy.zh-CN.html` returned HTTP 200 with a normal Mobile Safari User-Agent. Bare `curl` without a browser UA may get Cloudflare **403** — re-check in Safari / iPhone, not only with a bot client. |

Re-run the Safari check immediately before each submission upload.

## App Privacy questionnaire (App Store Connect)

Answer for the official hosted service **and every SDK in the submitted
archive** (including **LiveKit**). The current iOS target has no analytics or
advertising SDKs. Sign in with Apple uses Apple's AuthenticationServices.
Data below is collected by the Cheers service (and, for realtime voice, processed
via LiveKit infrastructure), linked to the user, used for **App Functionality**,
and **not used for Tracking**:

| Apple data type | Data | Why |
| --- | --- | --- |
| Contact Info | Email Address; Name | Account identity and support |
| User Content | Other User Content; Photos or Videos | Messages and files a user chooses to share on the service (web / other clients; iOS MVP has no composer upload yet) |
| User Content | **Audio Data** | LiveKit voice channels and optional composer dictation / speech recognition |
| Identifiers | User ID | Authentication, workspace authorization, account operations |
| Device ID | APNs device token and device name | Notification registration, only after permission is granted |

### Third-party / SDK disclosure notes for ASC

| SDK / system API | Declared use | Privacy impact |
| --- | --- | --- |
| LiveKit (SPM) | Realtime voice room media | Audio streams between the device and LiveKit for voice channels the user joins; not advertising |
| Speech framework (fallback dictation) | On-device / Apple speech path when no server STT adapter is configured | Processes spoken draft audio to text; gated by `NSSpeechRecognitionUsageDescription` |
| AuthenticationServices | Sign in with Apple | Apple account identifier + name/email the user shares |

**Do not** mark Microphone / Audio as “Not used” in ASC if the Archive still
embeds LiveKit and `NSMicrophoneUsageDescription`. That mismatch is a common
rejection reason.

### iOS system permissions in the current source

| Permission | Current use | Release decision |
| --- | --- | --- |
| Notifications | Optional approvals, mentions, direct-message and invite alerts | Keep optional; request only after sign-in, never gate core use on it |
| Microphone | Voice channels (LiveKit) and composer dictation | Keep `NSMicrophoneUsageDescription`; request only when the user starts voice / dictation |
| Speech Recognition | Fallback spoken-draft → text | Keep `NSSpeechRecognitionUsageDescription`; request only when that path runs |
| Camera | Not used | Do not add `NSCameraUsageDescription` |
| Photo Library | Not used (no iOS composer attach yet) | Do not add `NSPhotoLibraryUsageDescription` |
| Location, Contacts, Calendar, Bluetooth, Health, Tracking | Not used | Do not add the corresponding purpose strings or entitlements |

Network access is not an iOS consent dialog. The app communicates with the
configured Cheers server over HTTPS/WSS; the only HTTP exception is loopback
development. Microphone and speech access are user-granted and feature-scoped;
the app does not use camera, photo library, or tracking entitlements.

Before submission, release owner must reconfirm this list against the final
binary and production services. If a crash reporter, analytics SDK, advertising
SDK, payment SDK, or new media provider is added, update the App Privacy
questionnaire, `PrivacyInfo.xcprivacy`, and `website/privacy.html` first.

### External AI and remote-operation release gate

Cheers can forward channel content to an external agent selected by a workspace
owner. Apple requires clear disclosure and explicit permission before personal
data is shared with a third-party AI. Before enabling an external agent in a
channel with personal data, obtain and record participant consent, identify the
agent/provider, link its terms, and state the data scope. This is a release
implemented as a versioned per-user/channel/bot consent. The gateway enforces it
at dispatch time and iOS lets the user review or revoke it in Settings.

The iOS client retains urgent lock-screen Approve / Deny actions. Both require
device authentication, the action label says it approves a remote action, and
the APNs alert warns users to approve only recognized requests. The gateway
still verifies the owner/designated-approver role and pending request before it
relays a decision. In-app approval shows the command/diff, warns of remote
impact, and requires a second confirmation. Keep the remote-operation policy at
`https://www.tocheers.com/remote-operations.html` publicly available and link
it from the release website.

## App Review Information

The iOS app offers first-party username/email and password authentication plus
Sign in with Apple on official gateways that advertise a complete Apple server
configuration. Self-hosted gateways without the official private key remain
password-only. Review must cover password login, Sign in with Apple (when
shown), and in-app account deletion.

### Review account prep (owner-only — never commit secrets)

Create immediately before submission on **production**
(`https://www.tocheers.com/api/v1`):

1. Ordinary member (not admin), password auth, **no MFA / TOTP / passkey
   challenge**, no invite wall, no pending email verification that blocks login.
2. Member of one workspace with at least one populated channel (sample bot
   thread + a couple of human messages) so chat is demonstrable.
3. Optional: a pending approval request the reviewer can open in-app (describe
   steps in Notes if present).
4. Account must **not expire** during review (Apple can take days).
5. Paste username/password **only** into App Store Connect → App Review
   Information. Rotate or disable after approval if desired.

Template for **App Review Information → Notes** (edit as needed):

```text
Review account username/email: [create immediately before submission]
Review account password: [enter only in App Store Connect]
Server URL: https://www.tocheers.com/api/v1 (prefilled; leave as-is)

Primary path: Open the app → sign in with the review account → open the
pre-seeded channel → send a text message → open Settings → Privacy Policy /
Help & Support → Delete account (do not need to complete deletion if you
only verify the confirm sheet).

Sign in with Apple: use a separate Apple ID on the same production server if
the Sign in with Apple button is visible.

MVP scope: this build is chat, bots, and remote-action approvals. Composer
file attach / upload is not enabled on iOS yet; channel files may be viewed
when already present. Microphone is used only for optional LiveKit voice
channels and composer dictation (permission prompted at feature use).

Remote-operation policy: https://www.tocheers.com/remote-operations.html
```

## Production Archive / APNs checklist

Block upload until each item is checked on the release machine:

- [ ] Signing: App Store distribution certificate + App Store provisioning for
      `app.cheers.ios` with Push (`aps-environment` = production)
- [ ] Production APNs `.p8` (or equivalent) configured on the **production**
      gateway; a real-device notification received after opt-in
- [ ] Scheme = Release; Archive from Xcode → Organizer **Validate App** succeeds
- [ ] Organizer version/build matches `MARKETING_VERSION` /
      `CURRENT_PROJECT_VERSION`
- [ ] Upload to App Store Connect; wait for processing without missing-compliance
      warnings about microphone / tracking
- [ ] ASC App Privacy answers match this packet (Audio Data + Microphone used)

## Security release gate

Block submission until all items below are evidenced for production:

- HTTPS and WSS are enforced at the public gateway; iOS now rejects non-local
  `http://` server URLs so credentials cannot be sent over a clear-text remote
  connection.
- `CORS_ALLOWED_ORIGINS` is set to the exact production frontend origin, not a
  development fallback.
- Production secrets are unique and held in a secret manager: administrator
  password, PostgreSQL password, JWT RS256 keys, `SECRET_STORE_KEY`, S3 keys,
  APNs `.p8` credentials, and email-provider credentials. No development
  credentials or private key is present in the image, repository, logs, or
  review notes.
- The legacy `JWT_SECRET_KEY`/HS256 migration path is disabled after all active
  tokens have been migrated or expired.
- For internet-facing bot connectors, ACP capability delegation is required and
  connectors use a minimal environment allowlist and bounded workspace roots.
- A release candidate has passed the gateway test suite and a **real-device smoke
  test**: login, logout, session expiry, websocket reconnect, open/download or
  preview an **existing** channel file (composer **upload is out of scope for
  the iOS MVP** — do not block GA on attach), push opt-in/out, Apple
  sign-in/link/revoke when configured, and the Delete account confirm path.
- `tocheers@icloud.com` has an owner and a tested response process. Account
  deletion requests must be verified and tracked.

## Findings from the 2026-07-21 pre-release audit

The current codebase has meaningful controls: RS256 bearer-token authentication,
rate-limited login and registration, channel/file authorization checks,
gateway-proxied object storage, file response hardening, Keychain token storage,
and explicit CORS/WebSocket-origin controls. The two past M1 vulnerabilities
recorded in `docs/SECURITY_REVIEW_M1.md` are fixed, but that review is historical
and must not be treated as a production sign-off.

The release-blocking risks are operational configuration and agent execution
boundaries, not an excuse for a compatibility shim: a weak or leaked production
secret, permissive CORS, absent TLS, retained HS256 secret, or an overly broad
connector environment would undermine the existing code safeguards. The gates
above are therefore required evidence before GA.

## 2026-07-28 compliance alignment (pre-submit)

Closed in repo for this pass:

- Version strings driven by Xcode `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
- App Privacy packet + `PrivacyInfo.xcprivacy` declare **Audio Data**; Microphone
  / Speech documented as used
- Public privacy pages disclose voice / LiveKit / dictation
- Smoke gate no longer requires iOS composer upload
- Review Notes + Archive / APNs owner checklist added

Still owner-only (cannot be finished in Git):

- Create non-expiring production review account and paste into ASC
- Redeploy `website/` if production still serves the pre-voice privacy copy
- Real-device Release Archive → Validate → Upload
- Fill ASC App Privacy UI to match this packet
