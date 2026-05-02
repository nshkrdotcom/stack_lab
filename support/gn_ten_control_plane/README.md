# StackLab Gn-Ten Control Plane

`StackLab.GnTenControlPlane` records release-gate receipts for `ADDL` items,
scanner runs, package placement, atom cleanup, env remediation, workspace
build proof, and deployment proof.

## Phase

Owner phase: `ADDL-PHASE-02`, Phase 1, and Phase 16.

## Contract

Receipts use bounded states: `passed`, `failed`, `skipped`, `missing`, and
`not_applicable`. Required missing receipts keep the release open.

## QC

```bash
mix test
mix format --check-formatted
```
