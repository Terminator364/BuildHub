# Security and public-repository boundary

BuildHub is intentionally public, but product repositories and operational credentials are not.

## Never commit

- access credentials or private signing material;
- private product source code or private build payloads;
- personal data or private telemetry;
- production receipts exposing private filesystem identifiers.

Use environment variables or local secret stores for credentials. Public CI workflows must never print sensitive values.

If sensitive material is accidentally committed, rotate or revoke it before continuing.
