# Context ABI Proofs

StackLab proves that Context ABI contracts can move through the gn-ten stack
without leaking raw prompt, memory, provider payload, credential, or private
tool output.

## Proof Owners

StackLab owns proof fixtures, scanners, receipts, and proof-matrix rows. The
domain semantics remain in owner repos:

- AppKit owns product-safe context projections.
- Mezzanine owns admission and workflow truth.
- Citadel owns authority grants and denial posture.
- OuterBrain owns Context ABI packets and prompt artifact refs.
- AITrace owns bounded evidence and replay facts.

## Required Evidence

A green context proof records packet hash, authority ref, render refs, trace
ref, redaction posture, and no-bypass scanner results. Monolith and distributed
proofs compare semantic receipt fields, not placement or timing facts.

## Local QC

```bash
mix gn_ten.proofs.validate --json
mix test examples/context_abi_roundtrip
```
