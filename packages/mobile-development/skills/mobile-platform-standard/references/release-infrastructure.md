# Release infrastructure

Read when setting up Apple or Google accounts, API keys, beta lanes or EAS variables, or installing an .ipa from Windows. Account-level setup is shared by all fleet mobile products; create no per-product developer accounts.

## Apple

Automated release needs an App Store Connect team API key (Users and Access, Integrations, App Store Connect API, Team Keys). The private key downloads once. Store it in the secure credential system, never in a repository, and reference it by environment variable name in registry entries. It removes the interactive Apple login per run.

## Google

Use an organization Play Developer account (company details and a D-U-N-S number; allow lead time). An organization account avoids the personal-account closed-test requirement (12 testers for 14 days). Create it before the first submission.

```text
Play Console -> Play App Signing -> Google Cloud service account -> Play Console API access -> EAS Submit
```

The upload key and the app signing key differ. Android App Links verification must use the app signing key fingerprint; using the upload key sends links to the browser instead of the app.

## Beta lanes

```text
iOS      dev build -> TestFlight internal -> TestFlight external -> App Store
Android  dev APK   -> internal testing    -> closed testing      -> production
```

## EAS environment variables

```text
Account-wide   SENTRY_ORG, SHARED_API_DOMAIN, APPLE_TEAM_ID
Per project    EXPO_PUBLIC_API_URL, EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY,
               SENTRY_PROJECT, GOOGLE_SERVICES_JSON, GOOGLE_SERVICE_INFO_PLIST
```

`GOOGLE_SERVICES_JSON` and `GOOGLE_SERVICE_INFO_PLIST` are file variables. Anything prefixed `EXPO_PUBLIC_` is compiled into client JavaScript and is public however EAS stores it.

## Installing an .ipa from Windows

```powershell
py -m pip install --user --no-deps pymobiledevice3   # plain pip fails: pyimg4 needs lzfse and a C compiler
py -m pymobiledevice3 usbmux list
py -m pymobiledevice3 apps install <path-to-ipa>
```

An App Store Connect API key (or an exported `.p12`) removes the credential fetch. It holds a private key, so the account holder handles it, not an agent.
