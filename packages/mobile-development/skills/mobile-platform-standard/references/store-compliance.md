# Store compliance

Non-code work that gates submission. None of it is optional, and most of it
has a lead time longer than the build it blocks.

## Apple

Required before an App Store submission is reviewable:

- Privacy policy URL.
- App Privacy answers in App Store Connect, covering data collected by
  integrated third-party SDKs as well as first-party code.
- Privacy manifest (`PrivacyInfo.xcprivacy`) for the app and for any
  third-party SDK that requires one. An invalid manifest is rejected at
  upload, before review.
- Age rating and export-compliance answers.
- Review instructions plus a working demo account. For a product behind an
  organization or clinic boundary, the reviewer account must reach the
  workflow being demonstrated without a real customer record.
- Screenshots per required device class, description, keywords, support URL.

## Google

- Privacy policy URL.
- Data Safety form. The developer is responsible for third-party SDK behavior
  here too, not only first-party collection.
- Content rating questionnaire.
- App access credentials for review.
- Permissions declarations for any sensitive permission.
- Store listing assets and an active testing track.

## Account deletion

Google requires an app that allows account creation to offer **both** an
in-app deletion path and an externally reachable web deletion request. Both
must exist before submission:

```text
Settings -> Account -> Delete account
https://<product-domain>/account-deletion
```

For health or financial products, records retained for regulatory reasons may
be excluded from deletion, but the retention and its basis must be disclosed
on both surfaces. "We keep some data" without saying what or why does not
satisfy the requirement.

## Ordering

Privacy policy and account deletion are product work, not release work. They
block the first submission, so schedule them with the feature build rather
than with the store paperwork.
