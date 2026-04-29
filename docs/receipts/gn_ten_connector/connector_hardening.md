# gn-ten Connector Hardening Receipt

Schema: `gn_ten_connector_hardening_v1`

Profile: `assembled_offline`

Provider-free: `true`

## Scenarios

- `connector_provider_free`: fixture provider response normalizes without live-provider calls or public provider payloads.
- `connector_secret_lease`: public connector seam exposes only an opaque lease handle and lease expiry shape.
- `connector_token_budget`: over-budget fixture returns `budget_exhausted_fallback` before uncontrolled spend.
- `prompt_injection_defense`: untrusted content fixture is rejected without changing policy or expanding tools.

## Proof Posture

- `authoritative_audit?`: `false`
- `production_deployment_proven?`: `false`
- `live_provider_proven?`: `false`
- `raw_provider_payload_public?`: `false`

## Does Not Prove

- live provider behavior
- production credential handling
- audit-grade connector evidence
- provider billing correctness
