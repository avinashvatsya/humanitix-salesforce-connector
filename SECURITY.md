# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately using GitHub's
["Report a vulnerability"](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
flow on this repository, rather than opening a public issue. We aim to respond
within a few business days.

## How the connector handles secrets

- The Humanitix **API key is never stored in this repository or in metadata**. It
  is entered by an admin after install into the `Humanitix API` **External
  Credential** and stored encrypted by the Salesforce platform. Apex references
  the credential via `callout:HumanitixAPI` and never reads the key.
- Access to the callout principal is granted only through the
  `Humanitix_Integration_Admin` permission set.
- All connector Apex runs `with sharing` and enforces field-level security on
  writes via `Security.stripInaccessible`.
- The connector is **read-only** — it never writes back to Humanitix.

## Handling data

Sync logs may contain error messages. When sharing logs on an issue, redact any
API keys, personal data, or attendee information.
