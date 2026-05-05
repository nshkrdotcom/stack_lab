# StackLab Tenant Isolation Scanner

Phase 12 scanner package for credential lease, provider account, connector
binding, target attach, session, event, trace, receipt, product projection,
memory fact, micro-state, and deployment artifact tenant isolation.

The scanner emits gn-ten-compatible receipts and blocks release when any
tenant-sensitive fact lacks tenant scope or crosses tenants.

QC:

```bash
mix test
mix format --check-formatted
mix compile --warnings-as-errors
```
