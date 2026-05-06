# StackLab Gn-Ten Control Plane

`StackLab.GnTenControlPlane` records release-gate receipts for `ADDL` items,
scanner runs, package placement, atom cleanup, env remediation, workspace
build proof, and deployment proof.

`StackLab.GnTenReleaseProof` composes those receipts with SpecCells, scanner
refs, docs refs, QC refs, and fixture ids for adaptive Phase 16 release proof.
It returns `open_defect` when inherited defects remain, even when every
required fixture is mapped.

## Phase

Owner phase: `ADDL-PHASE-02`, Phase 1, and Phase 16.

## Contract

Receipts use bounded states: `passed`, `failed`, `skipped`, `missing`, and
`not_applicable`. Required missing receipts keep the release open.
Release proof claims must include SpecCell refs, fixture refs, scanner refs,
docs refs, QC refs, and receipt refs. Missing claim evidence keeps `AOC-048`
open.

## QC

```bash
mix test
mix format --check-formatted
```
