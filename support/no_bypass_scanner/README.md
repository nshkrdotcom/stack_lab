# StackLab Product No-Bypass Scanner

Phase 12 scanner package for product boundary no-bypass evidence.

The scanner checks product surfaces for direct provider SDK calls, direct
generated SDK calls, direct env auth lookup, direct runtime mutation, direct DB
access, and direct trace writes in governed workflows. It emits ref-only
receipts and blocks release when findings remain open.

QC:

```bash
mix test
mix format --check-formatted
mix compile --warnings-as-errors
```
