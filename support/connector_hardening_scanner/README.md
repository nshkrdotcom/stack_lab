# StackLab Connector Hardening Scanner

Owner phase: Phase 8, `ADDL-PHASE-16`.

This package emits ref-only connector hardening receipts for HTTP and GraphQL
SDK governed paths. It checks env-read, token-storage, direct-client, generated
runtime schema, auth parser, operation dispatch, retry, webhook, pagination,
telemetry, binding, lease, admission, tenant, target, and redaction evidence
without using pattern engines.

Receipts contain field names, proof refs, owner repos, package paths, and target
code paths. They do not store raw token values, auth headers, provider payloads,
or env values.

## QC

```bash
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix format --check-formatted
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix compile --warnings-as-errors
ASDF_ELIXIR_VERSION=1.19.5-otp-28 mix test
```
