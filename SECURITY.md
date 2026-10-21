# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report privately through GitHub's
[private vulnerability reporting](https://github.com/ZachGSnow/snow-tools/security/advisories/new).
Include what you found, how to reproduce it, and the impact you expect.

You can expect an acknowledgement within 7 days. Fixes are released as a patch version
and credited in the release notes unless you prefer otherwise.

## Supported versions

Only the latest release receives security fixes.

## Secrets

This repository never contains real credentials. Configuration is supplied through
gitignored files created from the `*.example` templates, or through environment variables.
Every push is scanned with [gitleaks](https://github.com/gitleaks/gitleaks).

## Local data

Snow Tools keeps your clipboard history, snippets and notes as plain files in the `data\`
folder next to the script. Nothing is sent anywhere, and nothing is encrypted. See
"Your data and privacy" in the README. Reports about the privacy guard (a copy that should
have been skipped but was recorded) are welcome.

## Local data

Snow Tools keeps your clipboard history, snippets and notes as plain files in the `data\`
folder next to the script. Nothing is sent anywhere, and nothing is encrypted. See
"Your data and privacy" in the README. Reports about the privacy guard (a copy that should
have been skipped but was recorded) are welcome.
