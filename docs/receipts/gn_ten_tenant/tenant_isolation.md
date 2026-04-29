# gn-ten Tenant Isolation Receipt

Schema: `gn_ten_tenant_isolation_v1`

Profile: `assembled_offline`

Provider-free: `true`

## Scenarios

- `tenant_isolation_read`: tenant A can read only tenant A records; tenant B
  record lookup returns `denied`.
- `tenant_isolation_write`: tenant A write into a tenant B record returns
  `tenant_mismatch`; same-tenant write remains allowed.
- `tenant_lease_handling`: tenant A lease use by tenant A is allowed; tenant B
  use of tenant A lease is denied.

## Does Not Prove

- production row-level security
- audit-grade tenant isolation
- live provider credential handling

## Posture

This is a local fixture receipt. It is safe as development evidence and proof
matrix evidence only. It is not authoritative audit truth and it does not prove
production deployment isolation.
