# 0016. Push notifications of silo-mobile through the Expo Push Service

- **Status:** Accepted
- **Date:** 2026-11-25
- **Applies to:** silo-server, silo-mobile, silo

## Context

When `silo-mobile` is in the background it holds no SSE stream ([ADR 0001](0001-sse-vs-websocket.md)), so new mail needs a push notification (the requirement of phase 6: a notification in under 10 s). Platform push (FCM on Android, APNs on iOS) works only with credentials that belong to the publisher of the app: an FCM token is bound to the Firebase project compiled into the APK, and APNs keys belong to the Apple developer account that signs the app. A self-hosted instance has neither. This was deferred decision 20 of the plan ("a push gateway for self-hosted instances"), left open in [ADR 0010](0010-react-native-for-silo-mobile.md).

Constraints: the administrator of a self-hosted instance configures nothing for push (no Firebase, Apple or Expo keys) and does not build the app; the phone user installs nothing but the app; the same mechanism should serve iOS later; the payload must carry no message content ([ADR 0007](0007-bearer-tokens-for-native-clients.md), [threat model](../threat-model.md)).

## Decision

**Silo sends push through the [Expo Push Service](https://docs.expo.dev/push-notifications/overview/); the app publisher owns the one-time configuration.**

- **Registration.** The app (`expo-notifications`) obtains an `ExpoPushToken` and registers it with `POST /devices` for its bearer session. A device belongs to exactly one session: the table `push_devices` (migration 000053) has `session_id` `UNIQUE` with `ON DELETE CASCADE`, so signing out or the expiry of the session ends the push. `provider` is constrained to `'expo'` (a column so that a second provider can be added), `account_ids bigint[]` with `NULL` meaning every account, `UNIQUE (provider, push_token)`. Other endpoints: `GET /devices/current`, `DELETE /devices/{id}`; `GET /meta` reports `push: {providers: ["expo"]}` (`[]` when push is off).
- **Sending.** The server posts to `https://exp.host/--/api/v2/push/send` **without any credential** and checks the receipts at `.../push/getReceipts` about 15 minutes later (queue job `push.receipts`); `DeviceNotRegistered` deletes the device. Expo forwards the message to FCM (Android), in the future to APNs (iOS). The job `push.notify` runs about 2 s after the new message, which collapses a burst into one notification per device and account. A notification is sent only for a new message that stayed in INBOX: not during the initial sync, not for messages taken by filters, and not for read or own messages.
- **Switch.** `SILO_PUSH_ENABLED` (default `true`); `false` removes the provider from `/meta` and `POST /devices` answers `403 push_disabled`. `SILO_PUSH_EXPO_SEND_URL` and `SILO_PUSH_EXPO_RECEIPTS_URL` exist for tests against a fake service only. The server contacts Expo only once a user has enabled notifications in the app.
- **Payload.** To Expo and Google go the device token, a generic localized title ("New message" / "N new messages", en and pl) and `data: {v: 1, type: "mail", accountId, threadId, count}` with opaque identifiers. **Never** the sender, subject, body or an e-mail address; the app fetches the content through the API.
- **Client.** A switch in Settings → Notifications with a choice of accounts, the Android channel `mail`, no system notification in the foreground (SSE is running), a tap opens the thread (`count === 1`) or the account's inbox. The build reads `SILO_GOOGLE_SERVICES_JSON` and `SILO_EAS_PROJECT_ID` at `expo prebuild`; without them the app works and push is unavailable.
- **The publisher's one-time setup:** an Expo project, a Firebase project, an FCM V1 key uploaded to Expo, and `google-services.json` plus the `projectId` in the build.

State at the time of the decision: implemented and covered by automated tests (2026-11-25), **not yet verified on a physical device** and not released. The phase 6 definition of done for push (a notification in under 10 s, checked on a device) is therefore not met yet.

Update 2026-11-26: checked end to end on an Android 15 emulator with Google Play services (debug build against the dev stack): a notification about 7 s after SMTP delivery with the app in the background and with its process killed, none in the foreground, one "N new messages" notification for several messages, a tap opens the thread or the inbox. A physical device and a release build are still unchecked.

## Consequences

- An administrator does nothing; the only requirement is outbound HTTPS to `exp.host`. A phone user installs only the app. iOS needs only the APNs key uploaded by the publisher to Expo.
- All instances share the publisher's Expo and Firebase projects: a common limit of 600 notifications per second per project, no SLA, and a dependency on Expo's availability and terms.
- Sending to Expo is not authenticated, so whoever knows a token can send a notification to that device. The token is known only to the user's own server; Expo's "enhanced push security" cannot be enabled because it needs a secret shared with the sender.
- Google Play Services are required: no push on phones without Google or in an F-Droid build.
- Push works only in a build with the publisher's `google-services.json` and `projectId`; a fork with a different package name needs its own Expo and Firebase projects.
- Privacy: Expo and Google see the token, the generic title and the opaque identifiers, and learn that a given device received mail at a given time, but nothing about its content. The [threat model](../threat-model.md) records this.
- The `provider` column leaves room for a second provider (for example UnifiedPush) without a schema change.

## Alternatives

- **FCM HTTP v1 directly from the server.** An FCM token is bound to the Firebase project compiled into the APK, so an administrator's keys do not fit the ready-made app (`SENDER_ID_MISMATCH`). It would require each administrator to build their own APK, or initializing Firebase at runtime with custom native code; it does not work on iOS anyway, because the APNs keys belong to the publisher.
- **UnifiedPush (for example ntfy).** No Google and no central project, but Android only, every user must install a distributor app, the server would have to encrypt Web Push itself (RFC 8291), and the library for Expo is immature. It remains a possible second provider (the `provider` column).
- **No external push** (a foreground service with a permanent SSE stream, or a periodic task). Battery cost and a permanent notification icon; a periodic task of at least 15 minutes cannot meet the under 10 s requirement; not feasible on iOS.
- **A central push gateway of the project.** The same trust and limits as Expo, but a service the project would have to run and pay for.
