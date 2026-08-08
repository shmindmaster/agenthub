# Release infrastructure

Account-level setup shared across every fleet mobile product. Establish it
once; do not create per-product developer accounts.

## Apple

An Apple Developer membership is one piece. Automated release also needs an
**App Store Connect team API key**:

```text
App Store Connect -> Users and Access -> Integrations
  -> App Store Connect API -> Team Keys -> Generate API Key
```

The private key downloads exactly once. Store it in the secure credential
system, never in a repository, and reference it by environment variable name
in any registry entry.

With the key in place, release tooling reaches App Store Connect without an
interactive Apple login per run.

## Google

Use an **organization** Play Developer account, not a personal one per
product. Organization verification requires company details and a D-U-N-S
number, which has its own lead time.

```text
Google Play Console
  -> Play App Signing
  -> Google Cloud service account
  -> Play Console API access
  -> EAS Submit
```

Play App Signing holds the real signing key for Play-distributed apps. The
upload key and the app signing key are different keys; Android App Links
verification must use the fingerprint of the **app signing** key, which is the
common failure when links open the browser instead of the app.

A newly created *personal* Play account carries an additional closed-test
requirement (12 testers for 14 days) before production access. An organization
account does not. This is a further reason to create the business account
before the first submission rather than after.

## Beta lanes

Establish both permanently rather than per release:

```text
iOS      dev build -> TestFlight internal -> TestFlight external -> App Store
Android  dev APK   -> internal testing    -> closed testing      -> production
```

TestFlight supports up to 100 internal and 10,000 external testers.

## EAS environment variables

Account-wide values belong at the account level, not duplicated per project:

```text
Account-wide   SENTRY_ORG, SHARED_API_DOMAIN, APPLE_TEAM_ID
Per project    EXPO_PUBLIC_API_URL, EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY,
               SENTRY_PROJECT, GOOGLE_SERVICES_JSON,
               GOOGLE_SERVICE_INFO_PLIST
```

`GOOGLE_SERVICES_JSON` and `GOOGLE_SERVICE_INFO_PLIST` are file variables.
Anything prefixed `EXPO_PUBLIC_` is compiled into client JavaScript and is
public regardless of how it is stored in EAS.
