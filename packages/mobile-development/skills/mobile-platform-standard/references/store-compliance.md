# Store compliance

Read when preparing a store submission. These items gate submission and have longer lead times than the build.

## Apple

- Privacy policy URL.
- App Privacy answers covering third-party SDKs as well as first-party code.
- Privacy manifest (`PrivacyInfo.xcprivacy`) for the app and each SDK that requires one; an invalid manifest is rejected at upload.
- Age rating and export-compliance answers.
- Review instructions and a working demo account. For a product behind an organization or clinic boundary, the account must reach the demonstrated workflow without a real customer record.
- Screenshots per device class, description, keywords, support URL.

## Google

- Privacy policy URL.
- Data Safety form, including third-party SDK behavior.
- Content rating questionnaire.
- App access credentials for review.
- Declarations for sensitive permissions.
- Store listing assets and an active testing track.

## Account deletion

An app that allows account creation needs both an in-app deletion path and a web deletion request, before submission:

```text
Settings -> Account -> Delete account
https://<product-domain>/account-deletion
```

For health or financial products, records retained for regulatory reasons may be excluded, but both surfaces must state what is retained and why.

Privacy policy and account deletion are product work: schedule them with the feature build, not with the store paperwork.
